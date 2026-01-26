import { memo } from 'react';
import {
  BaseEdge,
  getBezierPath,
  getStraightPath,
  getSmoothStepPath,
  Position,
  type EdgeProps,
} from '@xyflow/react';
import { useSettingsStore, type EdgeType } from '@/stores/settingsStore';
import { getTypeColor as getEdgeColor } from '@/lib/dataTypes';

function getEdgePath(
  edgeType: EdgeType,
  sourceX: number,
  sourceY: number,
  targetX: number,
  targetY: number,
  sourcePosition: Position,
  targetPosition: Position
): string {
  switch (edgeType) {
    case 'straight':
      return getStraightPath({ sourceX, sourceY, targetX, targetY })[0];
    case 'step':
      return getSmoothStepPath({
        sourceX,
        sourceY,
        targetX,
        targetY,
        sourcePosition,
        targetPosition,
        borderRadius: 0,
      })[0];
    case 'smoothstep':
      return getSmoothStepPath({
        sourceX,
        sourceY,
        targetX,
        targetY,
        sourcePosition,
        targetPosition,
        borderRadius: 8,
      })[0];
    case 'bezier':
    default:
      return getBezierPath({
        sourceX,
        sourceY,
        targetX,
        targetY,
        sourcePosition,
        targetPosition,
        curvature: 0.25,
      })[0];
  }
}

export const ColoredEdge = memo(({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  data,
  selected,
}: EdgeProps) => {
  const edgeType = useSettingsStore((s) => s.edgeType);

  const edgePath = getEdgePath(
    edgeType,
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition
  );

  const dataType = data?.dataType as string | undefined;
  const color = getEdgeColor(dataType);

  return (
    <BaseEdge
      id={id}
      path={edgePath}
      style={{
        stroke: color,
        strokeWidth: selected ? 3 : 2,
        strokeOpacity: selected ? 1 : 0.7,
        filter: selected ? `drop-shadow(0 0 4px ${color})` : undefined,
      }}
    />
  );
});

ColoredEdge.displayName = 'ColoredEdge';
