import type { Configuration } from "@azure/msal-browser";

const tenantId = import.meta.env.VITE_TENANT_ID ?? "common";
const clientId = import.meta.env.VITE_CLIENT_ID ?? "00000000-0000-0000-0000-000000000000";

export const msalConfig: Configuration = {
  auth: {
    clientId,
    authority: `https://login.microsoftonline.com/${tenantId}`,
    redirectUri: window.location.origin,
    postLogoutRedirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
};

export const apiScopes = [
  import.meta.env.VITE_API_SCOPE ?? "api://orbit-dashboard/access_as_user",
];
