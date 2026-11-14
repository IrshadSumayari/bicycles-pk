import React, { createContext, useContext, useEffect, useState } from 'react'
import { User as SupabaseUser, Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { User } from '../types'
import { usersService } from '../lib/services'
import { swalConfig } from '../lib/sweetAlert'
import { getErrorMessage } from '../lib/errors';

interface AuthContextType {
  user: SupabaseUser | null
  profile: User | null
  session: Session | null
  loading: boolean
  // false when the signed-in account is a website customer, not staff
  isStaffAccount: boolean
  // true until the project owner has set up the first administrator
  needsBootstrap: boolean
  // Administrators and managers must verify with an authenticator app:
  // 'enroll' = no authenticator yet, 'verify' = enter a code, 'ok' = verified or not required
  mfaStep: MfaStep
  refreshMfa: () => Promise<void>
  // 'confirm' means the account exists but its email code has not been entered yet
  signIn: (email: string, password: string) => Promise<AuthResult>
  confirmEmail: (email: string, code: string) => Promise<void>
  resendConfirmation: (email: string) => Promise<void>
  signOut: () => Promise<void>
  updateProfile: (updates: Partial<User>) => Promise<void>
}

export type AuthResult = 'signed_in' | 'confirm'
export type MfaStep = 'ok' | 'enroll' | 'verify'

// Must match current_app_role() in the database: these roles only take effect
// in a session verified with an authenticator code (AAL2).
const MFA_ROLES = ['admin', 'manager']

async function mfaStepFor(role: string | undefined): Promise<MfaStep> {
  if (!role || !MFA_ROLES.includes(role)) return 'ok'
  const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
  if (error) throw error
  if (data.currentLevel === 'aal2') return 'ok'
  return data.nextLevel === 'aal2' ? 'verify' : 'enroll'
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

// Helper function to convert auth error messages to user-friendly text
function getAuthErrorMessage(errorMessage: string): string {
  if (errorMessage.includes('Signups not allowed')) {
    return 'New sign-ups are disabled. Ask an administrator to create your account.'
  }
  if (errorMessage.includes('Invalid login credentials')) {
    return 'Invalid email or password. Please check your credentials and try again.'
  }
  if (errorMessage.includes('Email not confirmed')) {
    return 'Enter the 6-digit code we emailed you to activate your account.'
  }
  if (errorMessage.includes('Token has expired or is invalid')) {
    return 'That code is wrong or has expired. Send a new code and try again.'
  }
  if (errorMessage.includes('User already registered')) {
    return 'An account with this email already exists. Please sign in instead.'
  }
  if (errorMessage.includes('Password should be at least')) {
    return 'Password must be at least 12 characters long.'
  }
  if (errorMessage.includes('Invalid email')) {
    return 'Please enter a valid email address.'
  }
  if (errorMessage.includes('Too many requests')) {
    return 'Too many attempts. Please wait a few minutes before trying again.'
  }
  if (errorMessage.includes('Network error')) {
    return 'Network connection issue. Please check your internet connection.'
  }
  // Default fallback message
  return 'An unexpected error occurred. Please try again.'
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<SupabaseUser | null>(null)
  const [profile, setProfile] = useState<User | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  const [isStaffAccount, setIsStaffAccount] = useState(true)
  const [needsBootstrap, setNeedsBootstrap] = useState(false)
  const [mfaStep, setMfaStep] = useState<MfaStep>('ok')

  useEffect(() => {
    supabase.rpc('needs_bootstrap').then(({ data }) => setNeedsBootstrap(data === true))

    // Get initial session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session)
      setUser(session?.user ?? null)
      if (session?.user) {
        loadProfile(session.user.id)
      } else {
        setLoading(false)
      }
    })

    // Listen for auth changes
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session)
      setUser(session?.user ?? null)
      if (session?.user) {
        loadProfile(session.user.id)
      } else {
        setProfile(null)
        setIsStaffAccount(true)
        setMfaStep('ok')
        setLoading(false)
      }
    })

    return () => subscription.unsubscribe()
  }, [])

  async function loadProfile(userId: string) {
    try {
      const { data, error } = await supabase
        .from('users')
        .select('*')
        .eq('id', userId)
        .maybeSingle()

      if (error) throw error

      if (!data) {
        // Not staff: either a website customer, or a login whose account no
        // longer exists (e.g. deleted), which is simply signed out.
        const { data: customerAccount } = await supabase
          .from('customer_accounts')
          .select('id')
          .eq('id', userId)
          .maybeSingle()
        if (!customerAccount) {
          await supabase.auth.signOut()
          return
        }
      }

      setIsStaffAccount(!!data)
      setMfaStep(data?.active ? await mfaStepFor(data.role) : 'ok')
      if (!data) {
        setProfile(null)
      } else {
        setProfile({
          id: data.id,
          username: data.username,
          name: data.name,
          email: data.email,
          role: data.role as User['role'],
          permissions: data.permissions || [],
          active: data.active ?? true,
          lastLogin: data.last_login ? new Date(data.last_login) : undefined,
          avatar: data.avatar || undefined
        })
      }
    } catch (error) {
      console.error('Error loading profile:', error)
      swalConfig.error('Failed to load user profile. Please try logging in again.')
      setProfile(null)
    } finally {
      setLoading(false)
    }
  }

  async function signIn(email: string, password: string): Promise<AuthResult> {
    setLoading(true)
    try {
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
      })
      if (error?.message.includes('Email not confirmed')) {
        setLoading(false)
        swalConfig.info(getAuthErrorMessage(error.message))
        return 'confirm'
      }
      if (error) throw error

      // Show success toast with our styled config
      swalConfig.success('Welcome back! You have successfully signed in.');
      return 'signed_in'
    } catch (error) {
      setLoading(false)
      
      // Show error toast with our styled config
      swalConfig.error(`Sign In Failed: ${getAuthErrorMessage(getErrorMessage(error))}`);
      throw error
    }
  }

  async function confirmEmail(email: string, code: string) {
    setLoading(true)
    try {
      const { error } = await supabase.auth.verifyOtp({ email, token: code, type: 'signup' })
      if (error) throw error
      swalConfig.success('Email confirmed! You are now signed in.');
    } catch (error) {
      setLoading(false)
      swalConfig.error(`Confirmation Failed: ${getAuthErrorMessage(getErrorMessage(error))}`);
      throw error
    }
  }

  async function resendConfirmation(email: string) {
    try {
      const { error } = await supabase.auth.resend({ type: 'signup', email })
      if (error) throw error
      swalConfig.success(`A new code has been sent to ${email}.`);
    } catch (error) {
      swalConfig.error(`Could not send a new code: ${getAuthErrorMessage(getErrorMessage(error))}`);
      throw error
    }
  }

  async function signOut() {
    setLoading(true)
    try {
      const { error } = await supabase.auth.signOut()
      if (error) throw error
      
      // Show success toast with our styled config
      swalConfig.success('Signed Out! You have been successfully signed out.');
    } catch (error) {
      setLoading(false)
      
      // Show error toast with our styled config
      swalConfig.error(`Sign Out Failed: ${getAuthErrorMessage(getErrorMessage(error))}`);
      throw error
    }
  }

  async function refreshMfa() {
    setMfaStep(await mfaStepFor(profile?.role))
  }

  async function updateProfile(updates: Partial<User>) {
    if (!user) throw new Error('No user logged in')
    
    const updatedProfile = await usersService.update(user.id, updates)
    setProfile(updatedProfile)
  }

  const value = {
    user,
    profile,
    session,
    loading,
    isStaffAccount,
    needsBootstrap,
    mfaStep,
    refreshMfa,
    signIn,
    confirmEmail,
    resendConfirmation,
    signOut,
    updateProfile,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
