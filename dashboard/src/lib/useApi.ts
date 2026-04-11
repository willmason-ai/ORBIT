import { useMsal } from "@azure/msal-react";
import { useMemo } from "react";
import type { AxiosInstance } from "axios";
import { createApiClient } from "./api";

export function useApi(): AxiosInstance {
  const { instance } = useMsal();
  return useMemo(() => createApiClient(instance as any), [instance]);
}
