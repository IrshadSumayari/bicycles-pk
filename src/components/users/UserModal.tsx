import {Input}from'@/components/ui/input';
import { useUsers } from '../../lib/hooks/useUsers';
import React, { useState, useEffect } from 'react';
import { X, User, Mail, Lock, Shield, Crown } from 'lucide-react';
import { User as UserType } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { usersService, uploadAvatar } from '../../lib/services';
import { resizeImage } from '../../lib/images';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';

interface UserModalProps {
  isOpen: boolean;
  onClose: () => void;
  user?: UserType | null;
}

export function UserModal({ isOpen, onClose, user }: UserModalProps) {
  const { state } = useApp();
  const staff = useUsers(isOpen);
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);

  const handleAvatarFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setUploading(true);
    try {
      const url = await uploadAvatar(await resizeImage(file, 512));
      setFormData(prev => ({ ...prev, avatar: url }));
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setUploading(false);
    }
  };
  const [formData, setFormData] = useState({
    username: '',
    name: '',
    email: '',
    password: '',
    role: 'cashier' as UserType['role'],
    active: true,
    avatar: ''
  });

  useEffect(() => {
    if (user) {
      setFormData({
        username: user.username,
        name: user.name,
        email: user.email,
        password: '', // Don't pre-fill password for existing users
        role: user.role,
        active: user.active,
        avatar: user.avatar || ''
      });
    } else {
      setFormData({
        username: '',
        name: '',
        email: '',
        password: '',
        role: 'cashier',
        active: true,
        avatar: ''
      });
    }
  }, [user]);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user && staff.data?.some(existing => existing.username.toLowerCase() === formData.username.trim().toLowerCase())) {
      swalConfig.error('This username is already in use');
      return;
    }
    setLoading(true);

    try {
      if (user) {
        // Update existing user
        await usersService.update(user.id, {
          username: formData.username,
          name: formData.name,
          email: formData.email,
          role: formData.role,
          active: formData.active,
          avatar: formData.avatar || undefined
        });
        
      } else {
        // Create new user (server side, admin only)
        if (!formData.password || formData.password.length < 8) {
          swalConfig.error('Password must be at least 8 characters long');
          return;
        }

        await usersService.create({
          username: formData.username,
          name: formData.name,
          email: formData.email,
          password: formData.password,
          role: formData.role,
          active: formData.active,
          avatar: formData.avatar || undefined
        });

      }

      onClose();
    } catch (error) {
      swalConfig.error(`Error ${user ? 'updating' : 'creating'} user: ${getErrorMessage(error)}`);
    } finally {
      setLoading(false);
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const { name, value, type } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? (e.target as HTMLInputElement).checked : value
    }));
  };

  const rolePermissions = {
    admin: ['Full system access', 'User management', 'Settings configuration', 'All reports'],
    manager: ['Sales management', 'Inventory control', 'Customer management', 'Basic reports'],
    cashier: ['POS operations', 'Basic sales', 'Customer lookup', 'Receipt printing']
  };

  return (
    <div className="modal-overlay">
      <div className="modal max-w-2xl">
        <div className="modal-header">
          <h2 className="text-xl font-bold text-link flex items-center space-x-2">
            <User className="h-6 w-6 text-primary" />
            <span>{user ? 'Edit User' : 'Add New User'}</span>
          </h2>
          <button
            onClick={onClose}
            className="text-bodytext hover:text-bodytext transition-colors"
          >
            <X className="h-6 w-6" />
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          <div className="modal-body space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-link mb-2">
                Full Name *
              </label>
              <div className="relative">
                <User className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-bodytext" />
                <Input
                  type="text"
                  name="name"
                  value={formData.name}
                  onChange={handleChange}
                  required
                  className="input pl-10"
                  placeholder="Enter full name"
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-link mb-2">
                Username *
              </label>
              <Input
                type="text"
                name="username"
                value={formData.username}
                onChange={handleChange}
                required
                className="input"
                placeholder="Enter username"
                disabled={!!user} // Disable editing username for existing users
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-link mb-2">
                Email *
              </label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-bodytext" />
                <Input
                  type="email"
                  name="email"
                  value={formData.email}
                  onChange={handleChange}
                  required
                  className="input pl-10"
                  placeholder="Enter email address"
                  disabled={!!user} // Disable editing email for existing users
                />
              </div>
            </div>

            {/* Password Field - Only show for new users */}
            {!user && (
              <div>
                <label className="block text-sm font-medium text-link mb-2">
                  Password *
                </label>
                <div className="relative">
                  <Lock className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-bodytext" />
                  <Input
                    type="password"
                    name="password"
                    value={formData.password}
                    onChange={handleChange}
                    required={!user}
                    minLength={8}
                    className="input pl-10"
                    placeholder="Enter password (min 8 characters)"
                  />
                </div>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-link mb-2">
                Role *
              </label>
              <div className="relative">
                <Shield className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-bodytext" />
                <select
                  name="role"
                  value={formData.role}
                  onChange={handleChange}
                  className="select pl-10"
                  disabled={user?.id === state.currentUser?.id} // Prevent self-role change
                >
                  <option value="cashier">Cashier</option>
                  <option value="manager">Manager</option>
                  <option value="admin">Administrator</option>
                </select>
              </div>
            </div>
          </div>

          {/* Role Permissions Display */}
          <div className="bg-lightgray rounded-xl p-4">
            <h3 className="text-sm font-semibold text-link mb-3 flex items-center space-x-2">
              {formData.role === 'admin' && <Crown className="h-4 w-4 text-warning" />}
              {formData.role === 'manager' && <Shield className="h-4 w-4 text-primary" />}
              {formData.role === 'cashier' && <User className="h-4 w-4 text-bodytext" />}
              <span className="capitalize">{formData.role} Permissions</span>
            </h3>
            <ul className="text-xs text-bodytext space-y-1">
              {rolePermissions[formData.role].map((permission, index) => (
                <li key={index} className="flex items-center space-x-2">
                  <div className="w-1 h-1 bg-darkgray rounded-full"></div>
                  <span>{permission}</span>
                </li>
              ))}
            </ul>
          </div>

          <div>
            <label className="block text-sm font-medium text-link mb-2">
              Profile picture (Optional)
            </label>
            <div className="flex items-center gap-3">
              {formData.avatar ? (
                <img src={formData.avatar} alt="" className="w-12 h-12 rounded-full object-cover border border-border shrink-0" />
              ) : (
                <span className="w-12 h-12 rounded-full bg-lightprimary text-primary grid place-items-center shrink-0">
                  <User className="h-5 w-5" />
                </span>
              )}
              <label className={`btn btn-secondary btn-sm ${uploading || loading ? 'opacity-50 pointer-events-none' : 'cursor-pointer'}`}>
                {uploading ? 'Uploading…' : 'Upload from computer'}
                <input type="file" accept="image/*" className="sr-only" onChange={handleAvatarFile} disabled={uploading || loading} />
              </label>
              {formData.avatar && (
                <button type="button" className="text-sm text-error underline" onClick={() => setFormData(prev => ({ ...prev, avatar: '' }))}>
                  Remove
                </button>
              )}
            </div>
            <Input
              type="url"
              name="avatar"
              value={formData.avatar}
              onChange={handleChange}
              className="input mt-2"
              placeholder="Or paste an image link: https://…"
            />
          </div>

          <div className="flex items-center space-x-3">
            <Input
              type="checkbox"
              id="active"
              name="active"
              checked={formData.active}
              onChange={handleChange}
              className="rounded-sm border-border text-primary focus:ring-primary"
              disabled={user?.id === state.currentUser?.id} // Prevent self-deactivation
            />
            <label htmlFor="active" className="text-sm font-medium text-link">
              Active User
            </label>
          </div>

          </div>
          <div className="modal-footer">
            <button
              type="button"
              onClick={onClose}
              className="btn btn-secondary btn-md"
              disabled={loading}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="btn btn-primary btn-md"
              disabled={loading}
            >
              {loading ? 'Saving...' : (user ? 'Update User' : 'Create User')}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
