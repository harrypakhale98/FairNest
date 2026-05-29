# FairNest Website

This folder is a static website for FairNest. It can be published as-is on GitHub Pages, Netlify, Vercel, Cloudflare Pages, or any ordinary static host after a domain is purchased.

## Files

- `index.html` - product explainer homepage.
- `support.html` - App Store support page and contact surface.
- `privacy.html` - standalone privacy policy page.
- `styles.css` - responsive visual system.
- `script.js` - header and reveal behavior.
- `assets/` - local app icon and real iPhone screenshots.

## Local Preview

From the repository root:

```sh
python3 -m http.server 4173 --directory website
```

Then open:

```text
http://localhost:4173
```
