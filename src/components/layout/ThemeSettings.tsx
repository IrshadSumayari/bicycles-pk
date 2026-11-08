import { Sun, Moon, Monitor, PanelLeft } from "lucide-react";
import { useTheme } from "@/context/ThemeContext";
import { presets, type ThemeSettings as Preferences } from "@/lib/theme";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
const swatches = [
  "#635BFF",
  "#0074BA",
  "#763EBD",
  "#0a7ea4",
  "#01C0C8",
  "#FA896B",
];
export function ThemeSettings({
  open,
  onOpenChange,
  onSidebarChange,
}: {
  open: boolean;
  onOpenChange: (value: boolean) => void;
  onSidebarChange?: (value: Preferences["sidebar"]) => void;
}) {
  const { theme, setTheme } = useTheme();
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full sm:max-w-md overflow-y-auto p-6 bg-card">
        <SheetHeader>
          <SheetTitle>Theme settings</SheetTitle>
          <SheetDescription>Personalize this device</SheetDescription>
        </SheetHeader>
        <Separator className="my-6" />
        <h3 className="font-semibold mb-4">Theme mode</h3>
        <div className="grid grid-cols-3 gap-3">
          {(
            [
              ["light", Sun],
              ["dark", Moon],
              ["system", Monitor],
            ] as const
          ).map(([mode, Icon]) => (
            <Button
              key={mode}
              variant="outline"
              className={
                "h-24 flex-col capitalize " +
                (theme.mode === mode
                  ? "bg-lightprimary ring-2 ring-primary"
                  : "border-border text-link")
              }
              aria-pressed={theme.mode === mode}
              onClick={() => setTheme({ mode })}
            >
              <Icon size={24} />
              {mode}
            </Button>
          ))}
        </div>
        <h3 className="font-semibold mt-8 mb-4">Colour</h3>
        <div className="grid grid-cols-3 gap-4">
          {presets.map((preset, i) => (
            <button
              key={preset}
              className={
                "border rounded-tw p-4 flex justify-center " +
                (theme.preset === preset
                  ? "border-primary ring-2 ring-lightprimary"
                  : "border-border")
              }
              aria-label={preset.replace("_THEME", "").toLowerCase() + " theme"}
              aria-pressed={theme.preset === preset}
              onClick={() => setTheme({ preset })}
            >
              <span
                className="w-8 h-8 rounded-full"
                style={{ background: swatches[i] }}
              />
            </button>
          ))}
        </div>
        <h3 className="font-semibold mt-8 mb-4">Sidebar</h3>
        <div className="grid grid-cols-2 gap-3">
          {(["full", "mini"] as Preferences["sidebar"][]).map((sidebar) => (
            <Button
              key={sidebar}
              variant="outline"
              aria-pressed={theme.sidebar === sidebar}
              className={
                "capitalize h-20 flex-col " +
                (theme.sidebar === sidebar
                  ? "bg-lightprimary"
                  : "border-border text-link")
              }
              onClick={() => {
                setTheme({ sidebar });
                onSidebarChange?.(sidebar);
              }}
            >
              <PanelLeft />
              {sidebar}
            </Button>
          ))}
        </div>
      </SheetContent>
    </Sheet>
  );
}
