import type { AppSettings } from '../../types';
export interface SettingsSectionProps {
  value: AppSettings;
  onChange: (patch: Partial<AppSettings>) => void;
  admin: boolean;
}
