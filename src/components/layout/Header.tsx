import { useState, type ReactNode } from "react";
import {
  Menu,
  Sun,
  Moon,
  Palette,
  Monitor,
  Smartphone,
  ShoppingCart,
  Bell,
  LogOut,
  Settings as SettingsIcon,
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useApp } from "@/context/SupabaseAppContext";
import { useAuth } from "@/context/AuthContext";
import { useTheme } from "@/context/ThemeContext";
import { onlineOrdersService } from "@/lib/services";
import { queryKeys } from "@/lib/queryClient";
import { swalConfig } from "@/lib/sweetAlert";
import { ConnectionStatus } from "./ConnectionStatus";
import { navigation, canOpen } from "./navigation";
import { Sidebar } from "./Sidebar";
import { ThemeSettings } from "./ThemeSettings";
import {
  Sheet,
  SheetContent,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
export function Header({
  currentView,
  onViewChange,
  onOpenOnlineOrder,
  children,
}: {
  currentView: string;
  onViewChange: (view: string) => void;
  /** Opens Online orders at one order, or at the list when id is null. */
  onOpenOnlineOrder?: (id: string | null) => void;
  children: ReactNode;
}) {
  const { state, dispatch } = useApp(),
    { signOut } = useAuth(),
    { theme, dark, setTheme } = useTheme();
  const [mobile, setMobile] = useState(false),
    [customizer, setCustomizer] = useState(false),
    [expanded, setExpanded] = useState(false);
  const user = state.currentUser!;
  const mini = currentView === "pos" ? !expanded : theme.sidebar === "mini";
  const counter = ["admin", "manager", "cashier"].includes(user.role);
  const placed = useQuery({
    queryKey: queryKeys.onlineOrderList(user.id, {
      status: "placed",
      limit: 5,
    }),
    queryFn: () => onlineOrdersService.list({ status: "placed", limit: 5 }),
    enabled: counter,
    refetchInterval: 30_000,
  });
  const count = placed.data?.total_count ?? 0;
  const latest = placed.data?.orders ?? [];
  const openOnline = (id: string | null) =>
    onOpenOnlineOrder ? onOpenOnlineOrder(id) : onViewChange("online");
  async function logout() {
    const result = await swalConfig.confirm(
      "Sign Out Confirmation",
      "Are you sure you want to sign out? You will be logged out of the system.",
      "Sign Out",
    );
    if (result.isConfirmed) {
      try {
        await signOut();
      } catch (error) {
        console.error("Error signing out:", error);
        swalConfig.error("Failed to sign out. Please try again.");
      }
    }
  }
  const sideProps = {
    view: currentView,
    role: user.role,
    mini,
    name: user.name,
    store: state.settings.storeName,
    logo: state.settings.storeLogo,
    count,
    onView: onViewChange,
    onSignOut: () => void logout(),
  };
  return (
    <>
      <Sidebar {...sideProps} />
      <div className={"pos-main " + (mini ? "mini" : "")}>
        <header className="pos-header no-print">
          <button
            className="header-action"
            aria-label="Toggle sidebar"
            onClick={() => {
              if (matchMedia("(max-width:1023px)").matches) setMobile(true);
              else if (currentView === "pos") setExpanded(!expanded);
              else
                setTheme({
                  sidebar: theme.sidebar === "mini" ? "full" : "mini",
                });
            }}
          >
            <Menu size={20} />
          </button>
          <span className="font-semibold hidden sm:block">
            {navigation.find((n) => n.id === currentView)?.label}
          </span>
          <div className="ml-auto flex items-center gap-1 sm:gap-2">
            <ConnectionStatus />
            <button
              className="header-action"
              aria-label={dark ? "Switch to Light mode" : "Switch to Dark mode"}
              onClick={() => setTheme({ mode: dark ? "light" : "dark" })}
            >
              {dark ? <Sun size={20} /> : <Moon size={20} />}
            </button>
            <button
              className="header-action"
              aria-label="Theme settings"
              onClick={() => setCustomizer(true)}
            >
              <Palette size={20} />
            </button>
            <button
              className="header-action hidden md:flex"
              title={`Switch to ${state.settings.interfaceMode === "touch" ? "Traditional" : "Touch"} Mode`}
              onClick={() =>
                dispatch({
                  type: "SET_SETTINGS",
                  payload: {
                    interfaceMode:
                      state.settings.interfaceMode === "touch"
                        ? "traditional"
                        : "touch",
                  },
                })
              }
            >
              {state.settings.interfaceMode === "touch" ? (
                <Monitor size={20} />
              ) : (
                <Smartphone size={20} />
              )}
              <span className="sr-only">
                {state.settings.interfaceMode === "touch"
                  ? "Touch"
                  : "Traditional"}
              </span>
            </button>
            {currentView === "pos" && state.cart.length > 0 && (
              <span className="rounded-full px-3 py-2 bg-lightprimary text-primary flex gap-2">
                <ShoppingCart size={18} />
                {state.cart.reduce((n, i) => n + i.quantity, 0)}
              </span>
            )}
            {counter && (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button
                    className="header-action relative"
                    aria-label={
                      count > 0
                        ? `Online order notifications, ${count} new`
                        : "Online order notifications"
                    }
                  >
                    <Bell size={20} />
                    {count > 0 && (
                      <span className="absolute -top-1 -right-1 text-[10px] bg-error rounded-full text-white px-1.5">
                        {count}
                      </span>
                    )}
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent
                  align="end"
                  collisionPadding={12}
                  className="w-80 max-w-[calc(100vw-1.5rem)] p-2 bg-card"
                >
                  <DropdownMenuLabel>
                    {count > 0
                      ? `${count} new online order${count === 1 ? "" : "s"}`
                      : "No new online orders"}
                  </DropdownMenuLabel>
                  {latest.length > 0 && <DropdownMenuSeparator />}
                  {latest.map((order) => (
                    <DropdownMenuItem
                      key={order.id}
                      onSelect={() => openOnline(order.id)}
                      className="flex-col items-start gap-0.5"
                    >
                      <span className="flex w-full justify-between gap-2">
                        <span className="font-mono font-medium">
                          {order.order_no}
                        </span>
                        <span className="font-medium">
                          {state.settings.currency} {order.total.toFixed(2)}
                        </span>
                      </span>
                      <span className="text-xs text-bodytext truncate w-full">
                        {order.contact_name}
                        {order.phone ? ` · ${order.phone}` : ""}
                      </span>
                    </DropdownMenuItem>
                  ))}
                  <DropdownMenuSeparator />
                  <DropdownMenuItem
                    onSelect={() => openOnline(null)}
                    className="justify-center text-primary font-medium"
                  >
                    View all online orders
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            )}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button className="rounded-full ml-1" aria-label="Profile menu">
                  <Avatar>
                    {user.avatar && <AvatarImage src={user.avatar} alt="" className="object-cover" />}
                    <AvatarFallback className="bg-lightprimary text-primary font-bold">
                      {user.name
                        .split(" ")
                        .map((v) => v[0])
                        .slice(0, 2)
                        .join("")}
                    </AvatarFallback>
                  </Avatar>
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-64 p-3 bg-card">
                <DropdownMenuLabel>
                  <p>{user.name}</p>
                  <p className="font-normal text-xs text-bodytext">
                    {user.email}
                  </p>
                  <p className="capitalize text-primary text-xs mt-1">
                    {user.role}
                  </p>
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem onSelect={() => setCustomizer(true)}>
                  <Palette size={18} />
                  Theme settings
                </DropdownMenuItem>
                {canOpen(user.role, "settings") && (
                  <DropdownMenuItem onSelect={() => onViewChange("settings")}>
                    <SettingsIcon size={18} />
                    Settings
                  </DropdownMenuItem>
                )}
                <DropdownMenuItem onSelect={() => void logout()}>
                  <LogOut size={18} />
                  Sign Out
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </header>
        {children}
      </div>
      <Sheet open={mobile} onOpenChange={setMobile}>
        <SheetContent
          side="left"
          className="mobile-navigation p-0 w-[290px] bg-card"
        >
          <SheetTitle className="sr-only">Navigation</SheetTitle>
          <SheetDescription className="sr-only">
            Choose a screen
          </SheetDescription>
          <Sidebar
            {...sideProps}
            mini={false}
            onView={(view) => {
              onViewChange(view);
              setMobile(false);
            }}
          />
        </SheetContent>
      </Sheet>
      <ThemeSettings
        open={customizer}
        onOpenChange={setCustomizer}
        onSidebarChange={(sidebar) => setExpanded(sidebar === "full")}
      />
    </>
  );
}
