import {Input}from'@/components/ui/input';
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { RefreshCw } from 'lucide-react';
import { useApp } from '../../context/SupabaseAppContext';
import { rangeFor, type ReportPreset } from '../../lib/reportDates';
import { queryKeys } from '../../lib/queryClient';
import { SalesReport } from './SalesReport';
import { TendersReport } from './TendersReport';
import { ProductsReport } from './ProductsReport';
import { StaffReport } from './StaffReport';
import { ShiftHistory } from './ShiftHistory';

const tabs = [
  { id: 'sales', label: 'Sales', component: SalesReport },
  { id: 'payments', label: 'Payments', component: TendersReport },
  { id: 'products', label: 'Products', component: ProductsReport },
  { id: 'staff', label: 'Staff', component: StaffReport },
  { id: 'shifts', label: 'Shifts', component: ShiftHistory },
] as const;

export function ReportsManager() {
  const { state } = useApp();
  const user = state.currentUser;
  if (!user || !user.active || !['admin', 'manager'].includes(user.role)) {
    return (
      <div className="p-6">
        <div className="card p-6" role="status">
          Reports are for managers only.
        </div>
      </div>
    );
  }
  return (
    <ReportsScreen
      key={user.id}
      userId={user.id}
      currency={state.settings.currency}
    />
  );
}

function ReportsScreen({
  userId,
  currency,
}: {
  userId: string;
  currency: string;
}) {
  const queryClient = useQueryClient();
  const [preset, setPreset] = useState<ReportPreset>('today');
  const [range, setRange] = useState(() => rangeFor('today', new Date()));
  const [tab, setTab] = useState<(typeof tabs)[number]['id']>('sales');
  const [refreshing, setRefreshing] = useState(false);
  const validRange = Boolean(range.from && range.to && range.from <= range.to);
  const CurrentReport = tabs.find((item) => item.id === tab)!.component;
  return (
    <div className="p-4 lg:p-6 space-y-5 bg-lightgray min-h-full">
      <div className="flex flex-wrap justify-between items-start gap-3">
        <div>
          <p className="text-sm text-bodytext mt-1">
            Shop dates in Asia/Karachi · All your permitted branches
          </p>
        </div>
        <button
          type="button"
          className="btn btn-secondary btn-md"
          disabled={!validRange || refreshing}
          onClick={async () => {
            setRefreshing(true);
            try {
              await Promise.all([
                queryClient.invalidateQueries({ queryKey: queryKeys.allReports }),
                queryClient.invalidateQueries({ queryKey: queryKeys.shiftHistory }),
              ]);
            } finally {
              setRefreshing(false);
            }
          }}
        >
          <RefreshCw
            className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`}
            aria-hidden="true"
          />
          Refresh
        </button>
      </div>
      <div className="card p-4 flex flex-wrap items-end gap-4">
        <label className="space-y-1 text-sm font-medium">
          Period
          <select
            aria-label="Period"
            className="select block"
            value={preset}
            onChange={(event) => {
              const selected = event.target.value as ReportPreset;
              setPreset(selected);
              if (selected !== 'custom')
                setRange(rangeFor(selected, new Date()));
            }}
          >
            <option value="today">Today</option>
            <option value="yesterday">Yesterday</option>
            <option value="this_week">This week</option>
            <option value="this_month">This month</option>
            <option value="last_month">Last month</option>
            <option value="custom">Custom</option>
          </select>
        </label>
        {preset === 'custom' ? (
          <>
            <label className="space-y-1 text-sm font-medium">
              From
              <Input
                type="date"
                className="input block"
                value={range.from}
                max={range.to || undefined}
                onChange={(event) =>
                  setRange({ ...range, from: event.target.value })
                }
              />
            </label>
            <label className="space-y-1 text-sm font-medium">
              To
              <Input
                type="date"
                className="input block"
                value={range.to}
                min={range.from || undefined}
                onChange={(event) =>
                  setRange({ ...range, to: event.target.value })
                }
              />
            </label>
          </>
        ) : (
          <p className="text-sm text-bodytext py-3">
            {range.from} to {range.to}
          </p>
        )}
      </div>
      <nav
        className="flex gap-2 overflow-x-auto pb-1"
        aria-label="Report sections"
      >
        {tabs.map((item) => (
          <button
            key={item.id}
            type="button"
            aria-current={tab === item.id ? 'page' : undefined}
            className={`btn btn-md whitespace-nowrap ${tab === item.id ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setTab(item.id)}
          >
            {item.label}
          </button>
        ))}
      </nav>
      {validRange ? (
        <CurrentReport
          key={tab === 'shifts' ? `${tab}-${range.from}-${range.to}` : tab}
          {...range}
          currency={currency}
          userId={userId}
        />
      ) : (
        <p className="card p-5 text-warning" role="alert">
          Choose both dates, with the From date on or before the To date.
        </p>
      )}
    </div>
  );
}
