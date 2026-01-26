import { Handle, Position } from '@xyflow/react';
import { getHandleColor, type DataType } from './BaseNode';

const HANDLE_SIZE = 10;
const CONTENT_PADDING = 12; // p-3 = 12px

interface ParameterHandleProps {
  id: string;
  dataType: DataType;
}

/**
 * A handle for parameter inputs that positions itself at the left edge of the node,
 * vertically centered with its parent container.
 */
export function ParameterHandle({ id, dataType }: ParameterHandleProps) {
  return (
    <Handle
      type="target"
      position={Position.Left}
      id={id}
      data-handletype={dataType}
      style={{
        position: 'absolute',
        left: -CONTENT_PADDING,
        top: '50%',
        transform: 'translate(-50%, -50%)',
        background: getHandleColor(dataType),
        width: HANDLE_SIZE,
        height: HANDLE_SIZE,
        border: 'none',
        zIndex: 10,
      }}
      className="transition-transform hover:scale-125"
    />
  );
}
