import {
  LayoutDashboard,
  ShoppingCart,
  Package,
  Bike,
  Baby,
  Trophy,
  Zap,
  HardHat,
  Wrench,
  Receipt,
  Users,
  BarChart3,
  Percent,
  UserCog,
  Settings,
  type LucideIcon,
} from "lucide-react";
export type Role = "admin" | "manager" | "cashier";
export type View =
  | "dashboard"
  | "pos"
  | "online"
  | "transactions"
  | "inventory"
  | "bicycles"
  | "kids"
  | "sports"
  | "ebikes"
  | "accessories"
  | "parts"
  | "customers"
  | "commissions"
  | "reports"
  | "discounts"
  | "users"
  | "settings";
type Item = {
  id: View;
  label: string;
  icon: LucideIcon;
  section: "Sales" | "Catalogue" | "Management";
  roles: readonly Role[];
};
const managers = ["admin", "manager"] as const,
  counter = ["admin", "manager", "cashier"] as const;
export const navigation: readonly Item[] = [
  {
    id: "dashboard",
    label: "Dashboard",
    icon: LayoutDashboard,
    section: "Sales",
    roles: managers,
  },
  {
    id: "pos",
    label: "POS",
    icon: ShoppingCart,
    section: "Sales",
    roles: counter,
  },
  {
    id: "transactions",
    label: "Sales",
    icon: Receipt,
    section: "Sales",
    roles: managers,
  },
  {
    id: "online",
    label: "Online orders",
    icon: Package,
    section: "Sales",
    roles: counter,
  },
  {
    id: "inventory",
    label: "Inventory",
    icon: Package,
    section: "Catalogue",
    roles: managers,
  },
  {
    id: "bicycles",
    label: "Bicycles",
    icon: Bike,
    section: "Catalogue",
    roles: managers,
  },
  {
    id: "kids",
    label: "Kids",
    icon: Baby,
    section: "Catalogue",
    roles: managers,
  },
  {
    id: "sports",
    label: "Sports",
    icon: Trophy,
    section: "Catalogue",
    roles: managers,
  },
  {
    id: "ebikes",
    label: "E-bikes",
    icon: Zap,
    section: "Catalogue",
    roles: managers,
  },
  {
    id: "accessories",
    label: "Accessories",
    icon: HardHat,
    section: "Catalogue",
    roles: managers,
  },
  {
    id: "parts",
    label: "Parts",
    icon: Wrench,
    section: "Catalogue",
    roles: managers,
  },
  {
    id: "customers",
    label: "Customers",
    icon: Users,
    section: "Catalogue",
    roles: managers,
  },
  {
    id: "discounts",
    label: "Discounts",
    icon: Percent,
    section: "Catalogue",
    roles: managers,
  },
  {
    id: "reports",
    label: "Reports",
    icon: BarChart3,
    section: "Management",
    roles: managers,
  },
  {
    id: "commissions",
    label: "Commissions",
    icon: Percent,
    section: "Management",
    roles: counter,
  },
  {
    id: "users",
    label: "Users",
    icon: UserCog,
    section: "Management",
    roles: ["admin"],
  },
  {
    id: "settings",
    label: "Settings",
    icon: Settings,
    section: "Management",
    roles: managers,
  },
];
export function canOpen(role: Role | undefined, view: string): boolean {
  return (
    !!role && !!navigation.find((n) => n.id === view)?.roles.includes(role)
  );
}
export function defaultView(role: Role | undefined): View {
  return role === "admin" || role === "manager" ? "dashboard" : "pos";
}
