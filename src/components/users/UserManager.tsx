import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import { StatCard } from '@/components/shared/StatCard';
import { useUsers } from '../../lib/hooks/useUsers';
import { ReportStatus } from '../reports/ReportStatus';
import { useState } from 'react';
import { Plus, Search, Edit, Trash2, UserCheck, Crown, Shield, User } from 'lucide-react';
import { User as UserType } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { usersService } from '../../lib/services';
import { UserModal } from './UserModal';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';

export function UserManager() {
  const { state } = useApp();
  const query = useUsers();
  const users = query.data ?? [];
  const [searchTerm, setSearchTerm] = useState('');
  const [showUserModal, setShowUserModal] = useState(false);
  const [editingUser, setEditingUser] = useState<UserType | null>(null);
  const [loading, setLoading] = useState(false);

  const filteredUsers = users.filter(user =>
    user.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    user.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
    user.username.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const handleEditUser = (user: UserType) => {
    setEditingUser(user);
    setShowUserModal(true);
  };

  const handleDeleteUser = async (userId: string) => {
    if (userId === state.currentUser?.id) {
      swalConfig.warning('You cannot delete your own account');
      return;
    }

    const result = await swalConfig.deleteConfirm('user');
    if (result.isConfirmed) {
      setLoading(true);
      swalConfig.loading('Deleting user...');
      try {
        await usersService.delete(userId);
        swalConfig.success('User deleted successfully!');
      } catch (error) {
        swalConfig.error(`Error deleting user: ${getErrorMessage(error)}`);
      } finally {
        setLoading(false);
        swalConfig.close();
      }
    }
  };

  const handleAddUser = () => {
    setEditingUser(null);
    setShowUserModal(true);
  };

  const toggleUserStatus = async (user: UserType) => {
    if (user.id === state.currentUser?.id) {
      swalConfig.warning('You cannot deactivate your own account');
      return;
    }

    setLoading(true);
    swalConfig.loading(`${user.active ? 'Deactivating' : 'Activating'} user...`);
    try {
      await usersService.update(user.id, { active: !user.active });
      swalConfig.success(`User ${user.active ? 'deactivated' : 'activated'} successfully!`);
    } catch (error) {
      swalConfig.error(`Error updating user: ${getErrorMessage(error)}`);
    } finally {
      setLoading(false);
      swalConfig.close();
    }
  };

  const getRoleIcon = (role: string) => {
    switch (role) {
      case 'admin':
        return <Crown className="h-4 w-4" />;
      case 'manager':
        return <Shield className="h-4 w-4" />;
      default:
        return <User className="h-4 w-4" />;
    }
  };

  const getRoleColor = (role: string) => {
    switch (role) {
      case 'admin':
        return 'badge-warning';
      case 'manager':
        return 'badge-info';
      default:
        return 'badge-secondary';
    }
  };

  const activeUsers = users.filter(u => u.active).length;
  const adminUsers = users.filter(u => u.role === 'admin').length;
  const managerUsers = users.filter(u => u.role === 'manager').length;

  return (
    <div className="p-4 lg:p-6 space-y-6 bg-lightgray min-h-full">
      <ReportStatus loading={query.isPending} error={query.error} retry={() => void query.refetch()} />
      {/* Header */}
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center space-y-4 lg:space-y-0">
        <div>
          <p className="text-bodytext mt-1">Manage system users and their permissions</p>
        </div>
        
        <button
          onClick={handleAddUser}
          disabled={loading}
          className="btn btn-primary btn-lg disabled:opacity-50"
        >
          <Plus className="h-5 w-5" />
          <span>Add User</span>
        </button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 lg:gap-6">
        <StatCard label="Total Users" value={users.length} icon={<User size={22} />} tone="primary" progress={users.length ? 100 : 0} />
        <StatCard label="Active Users" value={activeUsers} icon={<UserCheck size={22} />} tone="success" progress={users.length ? (activeUsers / users.length) * 100 : 0} />
        <StatCard label="Admins" value={adminUsers} icon={<Crown size={22} />} tone="secondary" progress={users.length ? (adminUsers / users.length) * 100 : 0} />
        <StatCard label="Managers" value={managerUsers} icon={<Shield size={22} />} tone="warning" progress={users.length ? (managerUsers / users.length) * 100 : 0} />
      </div>

      {/* Controls */}
      <div className="card p-4 lg:p-6">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center space-y-4 sm:space-y-0 gap-4">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-bodytext h-5 w-5" />
            <Input
              type="text"
              placeholder="Search users..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="input pl-10"
            />
          </div>
        </div>
      </div>

      {/* Users Table */}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <DataTable className="table">
            <thead className="table-header">
              <tr>
                <th className="table-header-cell">User</th>
                <th className="table-header-cell">Role</th>
                <th className="table-header-cell">Last Login</th>
                <th className="table-header-cell">Status</th>
                <th className="table-header-cell text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="bg-card divide-y divide-border">
              {filteredUsers.map((user) => (
                <tr key={user.id} className="table-row">
                  <td className="table-cell">
                    <div className="flex items-center space-x-3">
                      <div className="h-10 w-10 bg-linear-to-br from-primary to-primary rounded-full flex items-center justify-center">
                        {user.avatar ? (
                          <img 
                            src={user.avatar} 
                            alt={user.name}
                            className="h-10 w-10 rounded-full object-cover"
                          />
                        ) : (
                          <span className="text-white font-bold text-sm">
                            {user.name.split(' ').map(n => n[0]).join('').toUpperCase()}
                          </span>
                        )}
                      </div>
                      <div>
                        <div className="text-sm font-semibold text-link">{user.name}</div>
                        <div className="text-xs text-bodytext">@{user.username}</div>
                        <div className="text-xs text-bodytext">{user.email}</div>
                      </div>
                    </div>
                  </td>
                  <td className="table-cell">
                    <span className={`badge ${getRoleColor(user.role)} flex items-center space-x-1`}>
                      {getRoleIcon(user.role)}
                      <span className="capitalize">{user.role}</span>
                    </span>
                  </td>
                  <td className="table-cell">
                    {user.lastLogin ? (
                      <div className="text-xs">
                        <div>{user.lastLogin.toLocaleDateString()}</div>
                        <div className="text-bodytext">{user.lastLogin.toLocaleTimeString()}</div>
                      </div>
                    ) : (
                      <span className="text-bodytext text-xs">Never</span>
                    )}
                  </td>
                  <td className="table-cell">
                    <button
                      onClick={() => toggleUserStatus(user)}
                      disabled={loading || user.id === state.currentUser?.id}
                      className={`badge ${
                        user.active ? 'badge-success' : 'badge-danger'
                      } cursor-pointer hover:opacity-80 disabled:cursor-not-allowed disabled:opacity-50`}
                    >
                      {user.active ? 'Active' : 'Inactive'}
                    </button>
                  </td>
                  <td className="table-cell text-right">
                    <div className="flex items-center justify-end space-x-2">
                      <button
                        onClick={() => handleEditUser(user)}
                        disabled={loading}
                        className="text-primary hover:text-primary p-2 rounded-lg hover:bg-lightprimary transition-colors disabled:opacity-50"
                      >
                        <Edit className="h-4 w-4" />
                      </button>
                      {user.id !== state.currentUser?.id && (
                        <button
                          onClick={() => handleDeleteUser(user.id)}
                          disabled={loading}
                          className="text-error hover:text-error p-2 rounded-lg hover:bg-lighterror transition-colors disabled:opacity-50"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </DataTable>
        </div>
      </div>

      <UserModal
        isOpen={showUserModal}
        onClose={() => setShowUserModal(false)}
        user={editingUser}
      />
    </div>
  );
}
