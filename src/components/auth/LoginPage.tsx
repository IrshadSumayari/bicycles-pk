import { Input } from "@/components/ui/input";
import React, { useState } from "react";
import { Lock, User, Mail, Eye, EyeOff } from "lucide-react";
import { PLATFORM_LOGO } from "@/lib/branding";
import { useAuth } from "../../context/AuthContext";
import { useApp } from "../../context/SupabaseAppContext";
import { swalConfig } from "../../lib/sweetAlert";
import { getErrorMessage } from "../../lib/errors";

export function LoginPage() {
  const { state } = useApp();
  const { signIn, signUp, confirmEmail, resendConfirmation, loading, needsBootstrap } = useAuth();
  const [isSignUp, setIsSignUp] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  // Email waiting for its confirmation code; null shows the normal form
  const [confirming, setConfirming] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [credentials, setCredentials] = useState({
    email: "",
    password: "",
    name: "",
    username: "",
  });

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    try {
      if (isSignUp) {
        if (!credentials.name.trim() || !credentials.username.trim()) {
          // Show validation error toast with our styled config
          swalConfig.warning(
            "Missing Information: Name and username are required",
          );
          return;
        }
        const result = await signUp(
          credentials.email,
          credentials.password,
          credentials.name,
          credentials.username,
        );
        if (result === "confirm") setConfirming(credentials.email);
      } else {
        const result = await signIn(credentials.email, credentials.password);
        if (result === "confirm") setConfirming(credentials.email);
      }
    } catch (error) {
      // Errors are now handled by the AuthContext with SweetAlert2 toasts
      console.debug(
        "Login error handled by AuthContext:",
        getErrorMessage(error),
      );
    }
  };

  const handleConfirm = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!confirming) return;
    try {
      await confirmEmail(confirming, code.trim());
      setConfirming(null);
      setCode("");
    } catch (error) {
      console.debug("Confirmation error handled by AuthContext:", getErrorMessage(error));
    }
  };

  const handleResend = async () => {
    if (!confirming) return;
    try {
      await resendConfirmation(confirming);
    } catch (error) {
      console.debug("Resend error handled by AuthContext:", getErrorMessage(error));
    }
  };

  const resetForm = () => {
    setCredentials({ email: "", password: "", name: "", username: "" });
  };

  const toggleMode = () => {
    setIsSignUp(!isSignUp);
    resetForm();
  };

  return (
    <div className="auth-screen">
      <section className="auth-brand">
        <div className="w-16 h-16 bg-white border border-border rounded-tw grid place-items-center mb-8">
          <img
            src={state.settings.storeLogo || PLATFORM_LOGO}
            alt="Store Logo"
            className="w-12 h-12 object-contain"
          />
        </div>
        <p className="text-primary font-semibold tracking-widest uppercase mb-4">
          {state.settings.storeName || "Bicycles POS"}
        </p>
        <p className="text-4xl font-bold leading-tight max-w-md">
          Your shop. Your team.
          <br />
          One connected workspace.
        </p>
        <p className="mt-6 text-bodytext max-w-sm">
          Sales, stock and online orders, together in one place.
        </p>
      </section>
      <section className="auth-form">
        <div className="w-full max-w-md animate-fade-in">
          <div className="text-center mb-6">
            <div className="inline-flex items-center justify-center w-16 h-16 bg-white border border-border rounded-2xl mb-4 shadow-lg">
              <img
                src={state.settings.storeLogo || PLATFORM_LOGO}
                alt=""
                className="h-11 w-11 object-contain"
              />
            </div>
            <h1 className="text-2xl font-bold text-link mb-2">Bicycles POS</h1>
            <p className="text-bodytext">
              {confirming
                ? "Confirm your email"
                : isSignUp
                  ? "Create your account"
                  : "Welcome back! Please sign in"}
            </p>
          </div>

          <div className="card p-8 shadow-lg border-0">
            {confirming ? (
              <form onSubmit={handleConfirm} className="space-y-5">
                <p className="text-sm text-bodytext">
                  We sent a 6-digit code to <strong className="text-link">{confirming}</strong>.
                  Enter it below to activate your account.
                </p>
                <div>
                  <label htmlFor="confirm-code" className="block text-sm font-semibold text-link mb-2">
                    Confirmation code
                  </label>
                  <Input
                    id="confirm-code"
                    value={code}
                    onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                    className="input h-11 text-center tracking-[0.5em] text-lg"
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    placeholder="000000"
                    required
                    minLength={6}
                    maxLength={6}
                    autoFocus
                  />
                </div>
                <button
                  type="submit"
                  disabled={loading || code.length !== 6}
                  className="btn btn-primary w-full h-11 font-semibold disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {loading ? "Confirming..." : "Confirm and sign in"}
                </button>
                <div className="flex justify-between text-sm">
                  <button type="button" onClick={handleResend} className="text-primary font-medium">
                    Send a new code
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setConfirming(null);
                      setCode("");
                      setIsSignUp(false);
                    }}
                    className="text-bodytext font-medium"
                  >
                    Back to sign in
                  </button>
                </div>
              </form>
            ) : (
            <form onSubmit={handleSubmit} className="space-y-5">
              {isSignUp && (
                <>
                  <div>
                    <label className="block text-sm font-semibold text-link mb-2">
                      Full Name
                    </label>
                    <div className="relative">
                      <User className="absolute left-3 top-1/2 transform -translate-y-1/2 text-bodytext h-4 w-4" />
                      <Input
                        type="text"
                        value={credentials.name}
                        onChange={(e) =>
                          setCredentials((prev) => ({
                            ...prev,
                            name: e.target.value,
                          }))
                        }
                        className="input pl-10 h-11"
                        placeholder="Enter your full name"
                        required
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-sm font-semibold text-link mb-2">
                      Username
                    </label>
                    <div className="relative">
                      <User className="absolute left-3 top-1/2 transform -translate-y-1/2 text-bodytext h-4 w-4" />
                      <Input
                        type="text"
                        value={credentials.username}
                        onChange={(e) =>
                          setCredentials((prev) => ({
                            ...prev,
                            username: e.target.value,
                          }))
                        }
                        className="input pl-10 h-11"
                        placeholder="Choose a username"
                        required
                      />
                    </div>
                  </div>
                </>
              )}

              <div>
                <label className="block text-sm font-semibold text-link mb-2">
                  Email
                </label>
                <div className="relative">
                  <Mail className="absolute left-3 top-1/2 transform -translate-y-1/2 text-bodytext h-4 w-4" />
                  <Input
                    type="email"
                    value={credentials.email}
                    onChange={(e) =>
                      setCredentials((prev) => ({
                        ...prev,
                        email: e.target.value,
                      }))
                    }
                    className="input pl-10 h-11"
                    placeholder="Enter your email"
                    required
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-semibold text-link mb-2">
                  Password
                </label>
                <div className="relative">
                  <Lock className="absolute left-3 top-1/2 transform -translate-y-1/2 text-bodytext h-4 w-4" />
                  <Input
                    type={showPassword ? "text" : "password"}
                    value={credentials.password}
                    onChange={(e) =>
                      setCredentials((prev) => ({
                        ...prev,
                        password: e.target.value,
                      }))
                    }
                    className="input pl-10 pr-12 h-11"
                    placeholder="Enter your password"
                    required
                    minLength={6}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3 top-1/2 transform -translate-y-1/2 text-bodytext hover:text-bodytext transition-colors"
                  >
                    {showPassword ? (
                      <EyeOff className="h-4 w-4" />
                    ) : (
                      <Eye className="h-4 w-4" />
                    )}
                  </button>
                </div>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="btn btn-primary w-full h-11 font-semibold shadow-md hover:shadow-lg disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center space-x-2"
              >
                {loading ? (
                  <>
                    <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                    <span>
                      {isSignUp ? "Creating Account..." : "Signing in..."}
                    </span>
                  </>
                ) : (
                  <span>{isSignUp ? "Create Account" : "Sign In"}</span>
                )}
              </button>
            </form>
            )}

            {/* Staff accounts are created by an administrator. Sign-up is only offered
              to create the very first (administrator) account. */}
            {confirming ? null : needsBootstrap ? (
              <div className="mt-6 text-center">
                <button
                  onClick={toggleMode}
                  className="text-sm text-primary hover:text-primary font-medium"
                >
                  {isSignUp
                    ? "Already have an account? Sign in"
                    : "First time setup? Create the administrator account"}
                </button>
              </div>
            ) : (
              <p className="mt-6 text-center text-sm text-bodytext">
                Need an account? Ask your store administrator.
              </p>
            )}
            <div className="mt-4 p-4 bg-linear-to-r from-lightgray to-lightgray rounded-xl border border-border">
              <p className="text-xs font-bold text-link mb-2 text-center">
                Need any help?
              </p>
              <p className="text-xs text-bodytext text-center">
                Our team is here to help you!
              </p>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
