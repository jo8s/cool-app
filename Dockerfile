# Tiny static site served by nginx.
FROM nginx:1.27-alpine

# Custom config: gzip + /healthz for Kubernetes probes + SPA-style fallback.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# The app itself (single self-contained file).
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://localhost/healthz || exit 1
