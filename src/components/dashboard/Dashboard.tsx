import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { RefreshCw, Receipt, ShoppingBag } from "lucide-react";
import { useApp } from "@/context/SupabaseAppContext";
import { reportsService, onlineOrdersService } from "@/lib/services";
import { queryKeys } from "@/lib/queryClient";
import {
  dashboardRange,
  salesStats,
  dailySeries,
  dayLabels,
  paymentMix,
} from "@/lib/dashboard";
import { CardBox, TitleIconCard } from "@/components/shared/CardBox";
import { StatCard } from "@/components/shared/StatCard";
import { DataTable } from "@/components/shared/DataTable";
import { EmptyState } from "@/components/shared/EmptyState";
import { Skeleton } from "@/components/ui/skeleton";
import { ReportStatus } from "@/components/reports/ReportStatus";
import { Chart } from "./Chart";
export default function Dashboard() {
  const { state } = useApp(),
    [period, setPeriod] = useState<"7" | "30" | "month">("7"),
    range = dashboardRange(period, new Date());
  const money = (n: number) => `${state.settings.currency} ${n.toFixed(2)}`;
  const query = useQuery({
    queryKey: queryKeys.reports("dashboard", range.from, range.to, {
      userId: state.currentUser?.id,
      period,
    }),
    queryFn: async () => {
      const [
        sales,
        previous,
        today,
        tenders,
        todayTenders,
        products,
        staff,
        placed,
        confirmed,
      ] = await Promise.all([
        reportsService.salesSummary(range.from, range.to),
        reportsService.salesSummary(range.previousFrom, range.previousTo),
        reportsService.salesSummary(range.today, range.today),
        reportsService.tenders(range.from, range.to),
        reportsService.tenders(range.today, range.today),
        reportsService.topItems(range.from, range.to, "style", 10),
        reportsService.staffSales(range.from, range.to),
        onlineOrdersService.list({ status: "placed", limit: 1 }),
        onlineOrdersService.list({ status: "confirmed", limit: 1 }),
      ]);
      return {
        sales,
        previous,
        today,
        tenders,
        todayTenders,
        products,
        staff,
        waiting: placed.total_count + confirmed.total_count,
      };
    },
    staleTime: 60_000,
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  });
  if (query.isPending)
    return (
      <div className="grid md:grid-cols-3 gap-6" aria-label="Loading dashboard">
        {Array.from({ length: 6 }, (_, i) => (
          <Skeleton key={i} className="h-56 rounded-tw" />
        ))}
      </div>
    );
  if (query.isError)
    return (
      <ReportStatus
        loading={false}
        error={query.error}
        retry={() => void query.refetch()}
      />
    );
  const data = query.data,
    stats = salesStats(data.today),
    mix = paymentMix(data.tenders);
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap gap-3 items-center justify-between">
        <p className="text-bodytext text-sm">
          Asia/Karachi · All your permitted branches
        </p>
        <div className="flex gap-3">
          <select
            className="select w-auto"
            aria-label="Dashboard period"
            value={period}
            onChange={(e) => setPeriod(e.target.value as typeof period)}
          >
            <option value="7">7 days</option>
            <option value="30">30 days</option>
            <option value="month">This month</option>
          </select>
          <button
            className="btn btn-secondary btn-md"
            onClick={() => void query.refetch()}
            disabled={query.isFetching}
          >
            <RefreshCw size={18} />
            Refresh
          </button>
        </div>
      </div>
      <div className="dashboard-grid">
        <CardBox className="dashboard-welcome col-span-12 lg:col-span-6">
          <span className="text-primary font-semibold text-xs uppercase tracking-widest">
            Overview
          </span>
          <h1 className="text-2xl font-bold mt-4">
            Welcome back, {state.currentUser?.name}
          </h1>
          <p className="mt-5 text-bodytext">Today&apos;s net sales</p>
          <p className="text-3xl font-bold my-2">{money(stats.net)}</p>
          <p className="text-sm text-bodytext">{stats.invoices} sales today</p>
        </CardBox>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3">
          <StatCard
            label="Average sale today"
            value={money(stats.average)}
            icon={<Receipt size={20} />}
          />
        </div>
        <div className="col-span-12 sm:col-span-6 lg:col-span-3">
          <StatCard
            label="Online orders waiting"
            value={data.waiting}
            icon={<ShoppingBag size={20} />}
            tone="warning"
          />
        </div>
        <CardBox className="col-span-12 lg:col-span-8">
          <h2 className="font-semibold text-lg mb-5">Revenue forecast</h2>
          <Chart
            type="bar"
            height={310}
            series={[
              {
                name: "This period",
                data: dailySeries(data.sales, range.from, range.days),
              },
              {
                name: "Previous period",
                data: dailySeries(
                  data.previous,
                  range.previousFrom,
                  range.days,
                ),
              },
            ]}
            options={{
              plotOptions: { bar: { borderRadius: 4, columnWidth: "45%" } },
              dataLabels: { enabled: false },
              xaxis: {
                categories: dayLabels(range.from, range.days),
                tickAmount: Math.min(range.days, 10),
              },
              yaxis: { labels: { formatter: (n) => money(n) } },
            }}
          />
        </CardBox>
        <CardBox className="col-span-12 lg:col-span-4">
          <h2 className="font-semibold text-lg mb-5">Payment mix</h2>
          {mix.length ? (
            <Chart
              type="donut"
              height={310}
              series={mix.map((r) => r.value)}
              options={{
                labels: mix.map((r) => r.label),
                legend: { position: "bottom" },
                dataLabels: { enabled: false },
                tooltip: { y: { formatter: (n) => money(n) } },
              }}
            />
          ) : (
            <EmptyState>No payments for this period.</EmptyState>
          )}
        </CardBox>
        <div className="col-span-12 lg:col-span-7">
          <TitleIconCard title="Top products" icon={<ShoppingBag size={20} />}>
            <p className="text-bodytext text-xs mb-4">
              All products · The current report does not provide categories
              or thumbnails.
            </p>
            <DataTable
              empty={
                !data.products.length ? "No sales for this period." : undefined
              }
            >
              <thead>
                <tr>
                  <th className="table-header-cell">Product</th>
                  <th className="table-header-cell">Quantity</th>
                  <th className="table-header-cell">Revenue</th>
                </tr>
              </thead>
              <tbody>
                {data.products.map((p) => (
                  <tr key={p.key} className="table-row">
                    <td className="table-cell whitespace-normal!">{p.label}</td>
                    <td className="table-cell">{p.quantity}</td>
                    <td className="table-cell">{money(p.net)}</td>
                  </tr>
                ))}
              </tbody>
            </DataTable>
          </TitleIconCard>
        </div>
        <CardBox className="col-span-12 lg:col-span-5">
          <h2 className="font-semibold text-lg mb-4">
            Today&apos;s tender totals
          </h2>
          {data.todayTenders.length ? (
            data.todayTenders.map((r) => (
              <div
                key={r.method}
                className="flex justify-between border-b border-border py-4"
              >
                <span className="capitalize">{r.method}</span>
                <strong>{money(r.net)}</strong>
              </div>
            ))
          ) : (
            <EmptyState>No payments today.</EmptyState>
          )}
        </CardBox>
        <CardBox className="col-span-12">
          <h2 className="font-semibold text-lg mb-4">Sales by staff</h2>
          {data.staff.length ? (
            <Chart
              type="bar"
              height={260}
              series={[
                { name: "Net sales", data: data.staff.map((r) => r.net_sales) },
              ]}
              options={{
                plotOptions: { bar: { horizontal: true, borderRadius: 4 } },
                xaxis: {
                  categories: data.staff.map((r) => r.name),
                  tickAmount: 3,
                  title: { text: state.settings.currency },
                  labels: { formatter: (v) => Number(v).toFixed(0) },
                },
                dataLabels: { enabled: false },
                tooltip: { y: { formatter: (n) => money(n) } },
              }}
            />
          ) : (
            <EmptyState>No staff sales for this period.</EmptyState>
          )}
        </CardBox>
      </div>
    </div>
  );
}
