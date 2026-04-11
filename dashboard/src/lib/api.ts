import axios, { AxiosInstance } from "axios";
import { PublicClientApplication } from "@azure/msal-browser";
import { apiScopes } from "./auth";

const baseURL = import.meta.env.VITE_API_BASE_URL ?? "";

export function createApiClient(msalInstance: PublicClientApplication): AxiosInstance {
  const client = axios.create({ baseURL });

  client.interceptors.request.use(async (config) => {
    const account = msalInstance.getActiveAccount();
    if (account) {
      try {
        const result = await msalInstance.acquireTokenSilent({
          scopes: apiScopes,
          account,
        });
        config.headers.set("Authorization", `Bearer ${result.accessToken}`);
      } catch {
        await msalInstance.acquireTokenRedirect({ scopes: apiScopes });
      }
    }
    return config;
  });

  return client;
}
