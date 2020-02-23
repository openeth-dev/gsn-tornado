perl -pi -e 's/(<script>window.__NUXT__)/<script src="gsn.js"><\/script> $1/' site/index.html
for d in site/_nuxt/*.js; do
	npx js-beautify $d > asd
	mv asd $d
done

