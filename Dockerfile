# Serves the public flavour of the exported game (build/public, made by `ops/build-web.sh public`,
# with its credits.txt and licenses.txt) as static files. The test flavour (build/web) is never
# shipped: there the page parameter probe=1 turns on the browser tests' probe.
FROM nginx:1.27-alpine
COPY ops/nginx.conf /etc/nginx/conf.d/default.conf
COPY build/public/ /usr/share/nginx/html/
