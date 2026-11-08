      try {
        var t = JSON.parse(localStorage.getItem("pos-theme-v1") || "null");
        if (
          !t ||
          !["light", "dark", "system"].includes(t.mode) ||
          ![
            "BLUE_THEME",
            "AQUA_THEME",
            "PURPLE_THEME",
            "GREEN_THEME",
            "CYAN_THEME",
            "ORANGE_THEME",
          ].includes(t.preset) ||
          !["full", "mini"].includes(t.sidebar)
        )
          t = { mode: "system", preset: "BLUE_THEME", sidebar: "full" };
        var d =
          t.mode === "dark" ||
          (t.mode === "system" &&
            matchMedia("(prefers-color-scheme: dark)").matches);
        document.documentElement.classList.toggle("dark", d);
        document.documentElement.dataset.colorTheme = t.preset;
        document.documentElement.style.colorScheme = d ? "dark" : "light";
      } catch (e) {
        document.documentElement.dataset.colorTheme = "BLUE_THEME";
        document.documentElement.classList.toggle(
          "dark",
          matchMedia("(prefers-color-scheme: dark)").matches,
        );
      }
