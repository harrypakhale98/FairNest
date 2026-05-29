# FairNest Website

This folder is a static website for FairNest. It can be published as-is on GitHub Pages, Netlify, Vercel, Cloudflare Pages, or any ordinary static host.

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

## GitHub Pages

The repository includes `.github/workflows/deploy-website.yml`, which publishes this folder with GitHub Pages.

1. In the GitHub repository settings, set Pages to deploy from GitHub Actions.
2. Push `main`, or run the `Deploy Website` workflow manually.
3. Use these App Store Connect URLs after the workflow succeeds:

```text
https://harrypakhale98.github.io/FairNest/support.html
https://harrypakhale98.github.io/FairNest/privacy.html
```
