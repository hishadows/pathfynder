#!/bin/sh
set -e
cd pathfynder-hq
npm install
npm run build
cd ..
rm -rf public
mkdir -p public
cp -r pathfynder-hq/dist/* public/
cp index.html dashboard.html explore.html explore-mock.js manage.html manage-mock.js join.html join-mock.js passenger.html passenger-mock.js logo.png qeurf7dcykqjs81ozsx2ll6h0fowru.html manifest.webmanifest sw.js notifications.html public/
cp -r icons js public/
