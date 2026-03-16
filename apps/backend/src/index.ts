import { Elysia } from "elysia";
import { cors } from "@elysiajs/cors";
import { staticPlugin } from "@elysiajs/static";

const app = new Elysia()
  .use(cors())
  .use(
    staticPlugin({
      assets: "../frontend/dist",
      prefix: "/",
    })
  )
  .get("/api/health", () => ({ status: "ok" }))
  .get("/api/templates", () => ({
    templates: [
      {
        id: "flat_bottom_pouch",
        name: "Flat Bottom Pouch",
        description: "平底袋包装模板",
        default_params: {
          width: 89,
          height: 239,
          gusset_depth: 71,
          top_seal_height: 30,
          bleed_margin: 3,
          safe_margin: 5,
        },
      },
    ],
  }))
  .listen(3000);

console.log(
  `🦊 Elysia is running at ${app.server?.hostname}:${app.server?.port}`
);
