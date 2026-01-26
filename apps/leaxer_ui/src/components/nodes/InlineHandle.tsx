import { Handle, Position } from '@xyflow/react';
import { getHandleColor, type DataType } from './BaseNode';

const HANDLE_SIZE = 10;

interface InlineHandleProps {
  id: string;
  type: 'source' | 'target';
  dataType: DataType;
}

/**
 * An inline handle that appears next to form fields.
 * The handle is positioned at the left/right edge of the node,
 * aligned vertically with its parent container.
 */
export function InlineHandle({ id, type, dataType }: InlineHandleProps) {
  const isTarget = type === 'target';

  return (
    <div
      className="relative flex-shrink-0"
      style={{ width: HANDLE_SIZE, height: HANDLE_SIZE }}
    >
      {/* Visual indicator that stays in flow */}
      <div
        className="w-full h-full rounded-full transition-transform hover:scale-125"
        style={{
          background: getHandleColor(dataType),
        }}
      />
      {/* Actual React Flow handle - invisible, at node edge */}
      <Handle
        type={type}
        position={isTarget ? Position.Left : Position.Right}
        id={id}
        data-handletype={dataType}
        style={{
          position: 'absolute',
          top: '50%',
          background: 'transparent',
          width: HANDLE_SIZE * 2,
          height: HANDLE_SIZE * 2,
          border: 'none',
          // Position at edge based on type
          ...(isTarget ? { left: '-12px' } : { right: '-12px' }),
          transform: 'translateY(-50%)',
        }}
      />
    </div>
  );
}
