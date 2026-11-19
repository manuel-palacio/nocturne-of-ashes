# Serves the exported game (build/web, made by ops/build-web.sh, with its credits.txt and
# licenses.txt) as static files.
FROM nginx:1.27-alpine
COPY ops/nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web/ /usr/share/nginx/html/
