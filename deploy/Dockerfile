# 前端建置 → nginx。映像來源全部走 public.ecr.aws（Docker Hub 在大陸機房不通）。
FROM public.ecr.aws/docker/library/node:22-alpine AS build

ARG NPM_REGISTRY=https://registry.npmmirror.com
ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_KEY

WORKDIR /app
COPY package.json package-lock.json ./
# 建置階段不需要 playwright / pglite / supabase CLI 這些測試相依
RUN npm config set registry "$NPM_REGISTRY" \
 && npm ci --omit=dev --no-audit --no-fund \
 && npm i --no-save --no-audit --no-fund \
      vite @vitejs/plugin-vue tailwindcss @tailwindcss/vite vite-plugin-pwa

COPY . .
RUN VITE_SUPABASE_URL="$VITE_SUPABASE_URL" \
    VITE_SUPABASE_KEY="$VITE_SUPABASE_KEY" \
    npx vite build

FROM public.ecr.aws/nginx/nginx:stable-alpine
COPY --from=build /app/dist /usr/share/nginx/html
