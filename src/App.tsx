import { useState, useEffect, lazy, Suspense } from "react";
import { ThemeProvider, useTheme } from "./context/ThemeContext";
import {
  canOpen,
  defaultView,
  navigation,
} from "./components/layout/navigation";
import { PageHeader } from "./components/shared/PageHeader";
const Dashboard = lazy(() => import("./components/dashboard/Dashboard"));
import { AuthProvider, useAuth } from "./context/AuthContext";
import { AppProvider, useApp } from "./context/SupabaseAppContext";
import { LoginPage } from "./components/auth/LoginPage";
import { Header } from "./components/layout/Header";
import { POSTerminal } from "./components/pos/POSTerminal";
const TransactionsManager = lazy(() =>
  import("./components/transactions/TransactionsManager").then((m) => ({
    default: m.TransactionsManager,
  })),
);
const InventoryManager = lazy(() =>
  import("./components/inventory/InventoryManager").then((m) => ({
    default: m.InventoryManager,
  })),
);
const CustomerManager = lazy(() =>
  import("./components/customers/CustomerManager").then((m) => ({
    default: m.CustomerManager,
  })),
);
const ReportsManager = lazy(() =>
  import("./components/reports/ReportsManager").then((m) => ({
    default: m.ReportsManager,
  })),
);
const Settings = lazy(() =>
  import("./components/settings/Settings").then((m) => ({
    default: m.Settings,
  })),
);
const DiscountManager = lazy(() =>
  import("./components/discounts/DiscountManager").then((m) => ({
    default: m.DiscountManager,
  })),
);
const UserManager = lazy(() =>
  import("./components/users/UserManager").then((m) => ({
    default: m.UserManager,
  })),
);
const OnlineOrders = lazy(() =>
  import("./components/online/OnlineOrders").then((m) => ({
    default: m.OnlineOrders,
  })),
);

const CommissionManager = lazy(() => import('./components/commissions/CommissionManager').then(m => ({ default: m.CommissionManager })));

function AppContent() {
  const { user, profile, loading, signOut, isStaffAccount } = useAuth();
  const { state } = useApp();
  const [currentView, setCurrentView] = useState<string>("");
  // Bumped on every bell pick so picking the same order again still reopens it.
  const [onlineTarget, setOnlineTarget] = useState<{ id: string | null; n: number }>({ id: null, n: 0 });
  const openOnlineOrder = (id: string | null) => {
    setOnlineTarget((t) => ({ id, n: t.n + 1 }));
    setCurrentView("online");
  };
  const { theme } = useTheme();
  const role = state.currentUser?.role;
  useEffect(() => {
    // A role/account change starts at its permitted default screen.
    setCurrentView(role ? defaultView(role) : "");
  }, [role, state.currentUser?.id]);
  useEffect(() => {
    if (role && !canOpen(role, currentView)) {
      setCurrentView(defaultView(role));
    }
  }, [role, currentView]);

  // Show loading spinner while auth is loading
  if (loading) {
    return (
      <div className="min-h-screen bg-lightgray flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
      </div>
    );
  }

  // Website customer accounts cannot use the POS
  if (user && !isStaffAccount) {
    return (
      <div className="min-h-screen bg-lightgray flex items-center justify-center p-4">
        <div className="bg-card rounded-2xl shadow-xs border border-border p-8 max-w-md text-center space-y-4">
          <h1 className="text-xl font-bold text-link">Not a staff account</h1>
          <p className="text-bodytext">
            This login belongs to a customer account. The POS is for store staff
            only.
          </p>
          <button
            onClick={() => signOut()}
            className="btn btn-secondary btn-md"
          >
            Sign out
          </button>
        </div>
      </div>
    );
  }

  // Accounts stay inactive until an administrator activates them
  if (user && profile && !profile.active) {
    return (
      <div className="min-h-screen bg-lightgray flex items-center justify-center p-4">
        <div className="bg-card rounded-2xl shadow-xs border border-border p-8 max-w-md text-center space-y-4">
          <h1 className="text-xl font-bold text-link">Account not active</h1>
          <p className="text-bodytext">
            Your account is waiting for an administrator to activate it. Please
            ask your store administrator.
          </p>
          <button
            onClick={() => signOut()}
            className="btn btn-secondary btn-md"
          >
            Sign out
          </button>
        </div>
      </div>
    );
  }

  // Show login page if no user is authenticated
  if (!user || !state.currentUser) {
    return <LoginPage />;
  }

  const view = canOpen(role, currentView) ? currentView : defaultView(role);
  const screens: Record<string, React.ReactNode> = {
    dashboard: (
      <Suspense
        fallback={
          <div className="card p-8 animate-pulse">Loading dashboard…</div>
        }
      >
        <Dashboard />
      </Suspense>
    ),
    pos: <POSTerminal />,
    online: <OnlineOrders target={onlineTarget} />,
    transactions: <TransactionsManager />,
    inventory: <InventoryManager key="inventory" />,
    bicycles: <InventoryManager key="bicycles" department="bicycles" />,
    kids: <InventoryManager key="kids" department="kids" />,
    sports: <InventoryManager key="sports" department="sports" />,
    ebikes: <InventoryManager key="ebikes" department="ebikes" />,
    accessories: <InventoryManager key="accessories" department="accessories" />,
    parts: <InventoryManager key="parts" department="parts" />,
    customers: <CustomerManager />,
    reports: <ReportsManager />,
    commissions: <CommissionManager />,
    discounts: <DiscountManager />,
    users: <UserManager />,
    settings: <Settings />,
  };
  return (
    <div
      className={state.settings.interfaceMode === "touch" ? "touch-mode" : ""}
      data-sidebar={theme.sidebar}
    >
      <Header
        currentView={view}
        onViewChange={(next) => {
          // Ordinary navigation opens Online orders at its list, not the last bell pick.
          setOnlineTarget((t) => (t.id ? { id: null, n: t.n + 1 } : t));
          setCurrentView(next);
        }}
        onOpenOnlineOrder={openOnlineOrder}
      >
        <main className={view === "pos" ? "till-content" : "page-content"}>
          {view !== "pos" && (
            <PageHeader
              title={navigation.find((n) => n.id === view)?.label ?? ""}
            />
          )}
          {state.loading ? (
            <div className="p-8" role="status">
              Loading…
            </div>
          ) : (
            <Suspense
              fallback={
                <div className="card p-8 animate-pulse" role="status">
                  Loading…
                </div>
              }
            >
              {screens[view]}
            </Suspense>
          )}
        </main>
      </Header>
    </div>
  );
}

function App() {
  return (
    <ThemeProvider>
      <AuthProvider>
        <AppProvider>
          <AppContent />
        </AppProvider>
      </AuthProvider>
    </ThemeProvider>
  );
}

export default App;
