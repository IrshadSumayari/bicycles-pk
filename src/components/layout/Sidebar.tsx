import { LogOut } from "lucide-react";
import { PLATFORM_LOGO } from "@/lib/branding";
import { navigation, canOpen, type Role } from "./navigation";
import {
  Tooltip,
  TooltipProvider,
  TooltipTrigger,
  TooltipContent,
} from "@/components/ui/tooltip";
type Props = {
  view: string;
  role: Role;
  mini: boolean;
  name: string;
  store: string;
  logo?: string;
  count: number;
  onView: (view: string) => void;
  onSignOut: () => void;
};
export function Sidebar({
  view,
  role,
  mini,
  name,
  store,
  logo,
  count,
  onView,
  onSignOut,
}: Props) {
  return (
    <aside
      className={"pos-sidebar no-print " + (mini ? "mini" : "")}
      aria-label="Main navigation"
    >
      <div className="flex items-center gap-3 min-h-12 mb-2">
        {logo ? (
          <img
            src={logo}
            alt="Store Logo"
            className="w-10 h-10 object-contain"
          />
        ) : (
          <span className="w-10 h-10 rounded-xl bg-white border border-border flex items-center justify-center shrink-0">
            <img src={PLATFORM_LOGO} alt="" className="w-7 h-7 object-contain" />
          </span>
        )}
        <span className="store-name font-bold text-lg truncate">{store}</span>
      </div>
      <TooltipProvider delayDuration={150}>
        <nav className="flex-1 overflow-y-auto">
          {(["Sales", "Catalogue", "Management"] as const).map((section) => {
            const items = navigation.filter(
              (n) => n.section === section && canOpen(role, n.id),
            );
            return (
              items.length > 0 && (
                <div key={section}>
                  <p className="nav-caption">{section}</p>
                  {items.map((item) => (
                    <Tooltip key={item.id}>
                      <TooltipTrigger asChild>
                        <button
                          className={
                            "nav-link " + (view === item.id ? "active" : "")
                          }
                          aria-current={view === item.id ? "page" : undefined}
                          aria-label={item.label}
                          onClick={() => onView(item.id)}
                        >
                          <item.icon
                            size={20}
                            strokeWidth={1.75}
                            className="shrink-0"
                          />
                          <span className="nav-label flex-1">{item.label}</span>
                          {item.id === "online" && count > 0 && (
                            <span
                              className="nav-label rounded-full bg-lightprimary px-2 text-xs"
                              aria-label={`${count} new orders`}
                            >
                              {count}
                            </span>
                          )}
                        </button>
                      </TooltipTrigger>
                      {mini && (
                        <TooltipContent side="right">
                          {item.label}
                        </TooltipContent>
                      )}
                    </Tooltip>
                  ))}
                </div>
              )
            );
          })}
        </nav>
      </TooltipProvider>
      <div className="sidebar-profile mt-5 p-4 bg-lightprimary rounded-tw flex items-center gap-3">
        <div className="min-w-0 flex-1">
          <p className="font-semibold truncate">{name}</p>
          <p className="text-bodytext text-xs capitalize">{role}</p>
        </div>
        <button title="Sign Out" aria-label="Sign Out" onClick={onSignOut}>
          <LogOut size={20} />
        </button>
      </div>
    </aside>
  );
}
