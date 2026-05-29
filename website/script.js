(function () {
  const header = document.querySelector("[data-header]");

  function syncHeader() {
    if (!header || header.classList.contains("is-solid")) return;
    header.classList.toggle("is-scrolled", window.scrollY > 10);
  }

  syncHeader();
  window.addEventListener("scroll", syncHeader, { passive: true });

  const revealTargets = document.querySelectorAll(
    ".signal-grid > div, .section-heading, .section-copy, .device-stage, .flow-step, .showcase-copy, .showcase-phone, .feature-card, .privacy-copy, .privacy-list > div, .waitlist-panel, .policy-hero, .policy-content > *"
  );

  revealTargets.forEach((element, index) => {
    element.classList.add("reveal-item");
    element.style.setProperty("--reveal-delay", `${Math.min(index % 8, 5) * 70}ms`);
  });

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      {
        rootMargin: "0px 0px -12% 0px",
        threshold: 0.16
      }
    );

    revealTargets.forEach((element) => observer.observe(element));
  } else {
    revealTargets.forEach((element) => element.classList.add("is-visible"));
  }

  if (window.lucide) {
    window.lucide.createIcons({
      attrs: {
        "aria-hidden": "true"
      }
    });
  }
})();
