.PHONY: docs documentation html_docs graphs

docs: documentation html_docs

PROTOS_DIR := $(abspath $(CURDIR)/../protos)

documentation:
	docker run --rm -v $(CURDIR):/out -v $(PROTOS_DIR):/protos pseudomuto/protoc-gen-doc --doc_opt=markdown,protocol.md rellm.proto authentication.proto visibility_moderation.proto permissions.proto users.proto media.proto messages.proto posts.proto events.proto groups.proto server_configuration.proto federation.proto sync.proto ai_providers.proto

html_docs: documentation
	npm i markdown-to-html-cli -g
	markdown-to-html --source protocol.md --output protocol.html --github-corners https://github.com/JonLatane/rellm --style 'markdown-style { padding-top: 40px!important; }' --title 'Rellm Protocol Documentation'
	node -e "const f='protocol.html'; const js=require('fs').readFileSync('toc-sidebar.js','utf8'); \
		require('fs').writeFileSync(f, require('fs').readFileSync(f,'utf8').replace('</body>', '<script>'+js+'</script></body>'));"

graphs:
	cd architecture && dot -Tsvg Kubernetes_Deployment.dot -o Kubernetes_Deployment.svg
	cd architecture && dot -Gdpi=150 -Twebp Kubernetes_Deployment.dot -o Kubernetes_Deployment.webp
	cd architecture && dot -Tsvg Traefik_Kubernetes_Deployment.dot -o Traefik_Kubernetes_Deployment.svg
	cd architecture && dot -Gdpi=150 -Twebp Traefik_Kubernetes_Deployment.dot -o Traefik_Kubernetes_Deployment.webp
	cd architecture && dot -Tsvg Service_Architecture.dot -o Service_Architecture.svg
	cd architecture && dot -Gdpi=150 -Twebp Service_Architecture.dot -o Service_Architecture.webp
#	cd architecture && neato -Tsvg Service_Architecture.dot -o Service_Architecture.svg

# Rasterize the Rellm icon (with its dusk-sky backdrop) for app-icon-shaped uses --
# app store listings, favicons, etc.
rellm_icon.png: rellm_icon.svg
	rsvg-convert -w 1024 -h 1024 rellm_icon.svg -o rellm_icon.png

# Rasterize the bare Rellm emblem (no backdrop, transparent background) for use anywhere
# a solid square doesn't fit -- READMEs, over light/dark themes, etc.
rellm_emblem.png: rellm_emblem.svg
	rsvg-convert -w 1024 -h 1024 rellm_emblem.svg -o rellm_emblem.png
