import { LookupManager } from './LookupManager';
import {Tabs,TabsList,TabsTrigger,TabsContent}from'@/components/ui/tabs';
import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { AppSettings } from '../../types';
import { settingsService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';
import { ReportStatus } from '../reports/ReportStatus';
import { StoreSection } from './StoreSection';
import { SalesTaxSection } from './SalesTaxSection';
import { ReceiptsSection } from './ReceiptsSection';
import { CashSection } from './CashSection';
import { GoLiveImport } from './GoLiveImport';
import { OnlineSection } from './OnlineSection';

export function Settings() {
  const { state } = useApp();
  const allowed =
    !!state.currentUser &&
    ['admin', 'manager'].includes(state.currentUser.role);
  const query = useQuery({
    queryKey: queryKeys.settings,
    queryFn: settingsService.get,
    enabled: allowed,
    refetchOnWindowFocus: false,
  });
  if (!allowed)
    return (
      <div className="p-6">
        <p className="card p-5">Settings are for managers only.</p>
      </div>
    );
  return (
    <div className="p-4 lg:p-6 space-y-5">
      <ReportStatus
        loading={query.isPending}
        error={query.error}
        retry={() => void query.refetch()}
      />
      {query.data && (
        <SettingsForm key={state.currentUser!.id} initial={query.data} />
      )}
    </div>
  );
}

function SettingsForm({ initial }: { initial: AppSettings }) {
  const { state, dispatch } = useApp();
  const queryClient = useQueryClient();
  const admin = state.currentUser?.role === 'admin';
  const [value, setValue] = useState(initial);
  const [changes, setChanges] = useState<Partial<AppSettings>>({});
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const [saving, setSaving] = useState(false);
  function onChange(patch: Partial<AppSettings>) {
    setValue((previous) => ({ ...previous, ...patch }));
    setChanges((previous) => ({ ...previous, ...patch }));
    setRequestId(crypto.randomUUID());
  }
  async function save() {
    if (saving || !Object.keys(changes).length) return;
    setSaving(true);
    try {
      const saved = await settingsService.update(changes, requestId);
      dispatch({ type: 'SET_SETTINGS', payload: saved });
      queryClient.setQueryData(queryKeys.settings, saved);
      setValue(saved);
      setChanges({});
      setRequestId(crypto.randomUUID());
      swalConfig.success('Settings saved successfully!');
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setSaving(false);
    }
  }
  const props = { value, onChange, admin };
  const [section,setSection]=useState('store');
  return (
    <div className="space-y-5">
      {!admin && (
        <p className="text-sm text-bodytext">
          You can manage lookups and receipt text. Other settings need an
          administrator.
        </p>
      )}
      <Tabs value={section} onValueChange={setSection} orientation="vertical" className="grid lg:grid-cols-[220px_1fr] gap-6"><TabsList className="flex flex-col items-stretch! justify-start! bg-card p-3 h-fit gap-2">{[['store','Store'],['sales','Sales & tax'],...(admin?[['online','Online orders']]:[]),['receipts','Receipts'],['cash','Cash'],['lookups','Lookups']].map(([id,label])=><TabsTrigger key={id} value={id} className="justify-start px-4 py-3 rounded-md data-[state=active]:bg-lightprimary data-[state=active]:text-primary">{label}</TabsTrigger>)}</TabsList><fieldset disabled={saving} className="space-y-5 min-w-0">
        <TabsContent value="store" forceMount hidden={section!=='store'}><StoreSection {...props}/></TabsContent>
        <TabsContent value="sales" forceMount hidden={section!=='sales'}><SalesTaxSection {...props}/></TabsContent>
        <TabsContent value="online" forceMount hidden={section!=='online'}><OnlineSection {...props}/></TabsContent>
        <TabsContent value="receipts" forceMount hidden={section!=='receipts'}><ReceiptsSection {...props}/></TabsContent>
        <TabsContent value="cash" forceMount hidden={section!=='cash'}><CashSection {...props}/></TabsContent>
        <TabsContent value="lookups" forceMount hidden={section!=='lookups'}><LookupManager /></TabsContent>
      </fieldset></Tabs>
      <div className="sticky bottom-4 z-10 flex justify-end">
        <button
          type="button"
          onClick={save}
          disabled={saving || !Object.keys(changes).length}
          className="btn btn-primary btn-md shadow-lg"
        >
          {saving ? 'Saving…' : 'Save settings'}
        </button>
      </div>
      {admin && <GoLiveImport />}
    </div>
  );
}
