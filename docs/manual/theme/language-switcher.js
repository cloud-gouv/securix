// SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
// SPDX-License-Identifier: CC-BY-SA-4.0

const LANGUAGES = [
  { code: "en", label: "EN" },
  { code: "fr", label: "FR" },
];

const getCurrentLang = () => {
  const path = window.location.pathname;
  if (path.includes("/fr/")) return "fr";
  if (path.includes("/en/")) return "en";
  return document.documentElement.lang === "fr" ? "fr" : "en";
};

const counterpartUrl = (targetLang) => {
  const currentLang = getCurrentLang();
  if (currentLang === targetLang) return window.location.href;
  const url = new URL(window.location.href);
  url.pathname = url.pathname.replace(`/${currentLang}/`, `/${targetLang}/`);
  return url.toString();
};

const initLanguageSwitcher = () => {
  const menuBar = document.getElementById("menu-bar") ?? document.querySelector(".menu-bar");
  if (!menuBar || document.getElementById("language-switcher")) return;

  const currentLang = getCurrentLang();
  const container = document.createElement("div");
  container.id = "language-switcher";
  container.className = "language-switcher";
  container.setAttribute("role", "navigation");
  container.setAttribute("aria-label", "Language switcher");

  for (const lang of LANGUAGES) {
    const a = document.createElement("a");
    a.href = counterpartUrl(lang.code);
    a.textContent = lang.label;
    a.lang = lang.code;
    a.hreflang = lang.code;
    a.className = "language-switcher__link";
    if (lang.code === currentLang) {
      a.classList.add("is-active");
      a.setAttribute("aria-current", "true");
      a.addEventListener("click", (e) => e.preventDefault());
    }
    a.title = lang.code === "fr" ? "Passer en français" : "Switch to English";
    container.appendChild(a);
  }

  const rightButtons = menuBar.querySelector(".right-buttons");
  if (rightButtons) {
    rightButtons.prepend(container);
  } else {
    menuBar.appendChild(container);
  }
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initLanguageSwitcher);
} else {
  initLanguageSwitcher();
}
