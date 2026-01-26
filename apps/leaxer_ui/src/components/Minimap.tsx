import { MiniMap as ReactFlowMiniMap } from '@xyflow/react';
import { useSettingsStore } from '@/stores/settingsStore';

export function Minimap() {
  const showMinimap = useSettingsStore((s) => s.showMinimap);

  if (!showMinimap) return null;

  return (
    <ReactFlowMiniMap
      className="minimap-styled"
      maskColor="rgba(0, 0, 0, 0.25)"
      nodeColor={(node) => {
        if (node.type === 'Group') {
          return 'rgba(255, 255, 255, 0.15)';
        }
        return 'rgba(255, 255, 255, 0.4)';
      }}
      nodeBorderRadius={4}
      nodeStrokeWidth={0}
      pannable
      zoomable
    />
  );
}
