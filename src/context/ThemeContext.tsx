import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { parseTheme, isDark, type ThemeSettings } from "@/lib/theme";
const ThemeContext = createContext<{
  theme: ThemeSettings;
  dark: boolean;
  setTheme: (patch: Partial<ThemeSettings>) => void;
} | null>(null);
export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setValue] = useState(() => {
    try {
      return parseTheme(localStorage.getItem("pos-theme-v1"));
    } catch {
      return parseTheme(null);
    }
  });
  const [systemDark, setSystemDark] = useState(
    () => matchMedia("(prefers-color-scheme: dark)").matches,
  );
  const dark = isDark(theme.mode, systemDark);
  useEffect(() => {
    const media = matchMedia("(prefers-color-scheme: dark)"),
      update = () => setSystemDark(media.matches);
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  useEffect(() => {
    document.documentElement.classList.toggle("dark", dark);
    document.documentElement.dataset.colorTheme = theme.preset;
    document.documentElement.style.colorScheme = dark ? "dark" : "light";
    try {
      localStorage.setItem("pos-theme-v1", JSON.stringify(theme));
    } catch {
      /* Device storage may be unavailable. */
    }
  }, [theme, dark]);
  return (
    <ThemeContext.Provider
      value={{
        theme,
        dark,
        setTheme: (patch) => setValue((v) => ({ ...v, ...patch })),
      }}
    >
      {children}
    </ThemeContext.Provider>
  );
}
// This hook is shared by the application shell and lazy chart boundary.
// eslint-disable-next-line react-refresh/only-export-components
export function useTheme() {
  const value = useContext(ThemeContext);
  if (!value) throw Error("ThemeProvider is required");
  return value;
}
