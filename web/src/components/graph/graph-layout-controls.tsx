import { createContext, useContext } from "react";

export type LayoutControls = {
  toggleGroup: (groupKey: string) => void;
};

export const LayoutControlsContext = createContext<LayoutControls>({
  toggleGroup: () => {},
});

export function useLayoutControls() {
  return useContext(LayoutControlsContext);
}
