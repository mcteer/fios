import { useCallback, useEffect, useRef, useState } from "react";

export const MODEL_REFRESH_MS = 30_000;

export function useModelCatalog(request) {
  const [models, setModels] = useState([]);
  const [selected, setSelected] = useState(
    () => localStorage.getItem("fios-model") || "",
  );
  const [modelsState, setModelsState] = useState("loading");
  const [modelsError, setModelsError] = useState("");
  const mounted = useRef(true),
    inFlight = useRef(null),
    initialized = useRef(false);

  const refreshModels = useCallback(async () => {
    if (inFlight.current) return;
    const controller = new AbortController();
    inFlight.current = controller;
    const timeout = setTimeout(() => controller.abort(), 12_000);
    try {
      const payload = await request("/models", {
        signal: controller.signal,
        cache: "no-store",
      });
      if (!Array.isArray(payload.models))
        throw new Error("Invalid model catalog received.");
      if (!mounted.current || inFlight.current !== controller) return;
      setModels(payload.models);
      setModelsState("ready");
      setModelsError("");
    } catch (error) {
      if (!mounted.current || inFlight.current !== controller) return;
      setModelsState("error");
      setModelsError(
        "Model discovery unavailable. Retrying automatically. " +
          (error.name === "AbortError"
            ? "The request timed out."
            : error.message),
      );
    } finally {
      clearTimeout(timeout);
      if (inFlight.current === controller) inFlight.current = null;
    }
  }, [request]);

  useEffect(() => {
    mounted.current = true;
    const whenVisible = () => {
      if (document.visibilityState === "visible") void refreshModels();
    };
    void refreshModels();
    const timer = setInterval(whenVisible, MODEL_REFRESH_MS);
    document.addEventListener("visibilitychange", whenVisible);
    window.addEventListener("focus", whenVisible);
    window.addEventListener("online", whenVisible);
    return () => {
      mounted.current = false;
      clearInterval(timer);
      document.removeEventListener("visibilitychange", whenVisible);
      window.removeEventListener("focus", whenVisible);
      window.removeEventListener("online", whenVisible);
      inFlight.current?.abort();
      inFlight.current = null;
    };
  }, [refreshModels]);

  useEffect(() => {
    if (modelsState !== "ready") return;
    if (!initialized.current) {
      initialized.current = true;
      // Only initial discovery can choose a default. Never silently replace a removed model.
      if (!selected) {
        setSelected(
          models.find((model) => model.loaded)?.id || models[0]?.id || "",
        );
        return;
      }
    }
    if (selected && !models.some((model) => model.id === selected))
      setSelected("");
  }, [models, modelsState, selected]);

  useEffect(() => {
    if (selected) localStorage.setItem("fios-model", selected);
    else localStorage.removeItem("fios-model");
  }, [selected]);

  return {
    models,
    selected,
    setSelected,
    modelsState,
    modelsError,
    refreshModels,
  };
}
