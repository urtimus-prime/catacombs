import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { init } from "@dojoengine/sdk";
import { DojoSdkProvider } from "@dojoengine/sdk/react";
import { dojoConfig, RPC_URL, TORII_URL } from "./dojo/config";
import { type SchemaType } from "./dojo/models";
import { setupWorld } from "./dojo/contracts";
import StarknetProvider from "./starknet";
import App from "./App";

async function main() {
  const sdk = await init<SchemaType>({
    client: {
      worldAddress: dojoConfig.manifest.world.address,
      toriiUrl: TORII_URL,
    },
    domain: {
      name: "catacombs",
      version: "1.0",
      chainId: "KATANA",
      revision: "1",
    },
  });

  createRoot(document.getElementById("root")!).render(
    <StrictMode>
      <DojoSdkProvider sdk={sdk} dojoConfig={dojoConfig} clientFn={setupWorld}>
        <StarknetProvider>
          <App />
        </StarknetProvider>
      </DojoSdkProvider>
    </StrictMode>
  );
}

main().catch((e) => {
  console.error("Failed to initialize:", e);
  document.getElementById("root")!.innerHTML =
    `<pre style="color:red;padding:20px">Failed to initialize:\n${e.message}\n${e.stack}</pre>`;
});
