export interface NodeData {
  [key: string]: unknown;
}

export interface GraphNode {
  id: string;
  type: string;
  position: { x: number; y: number };
  data: NodeData;
}

export interface GraphEdge {
  id: string;
  source: string;
  sourceHandle: string;
  target: string;
  targetHandle: string;
}

// Progress types
export interface GraphProgressData {
  current_index: number;
  total_nodes: number;
  percentage: number;
}

export interface NodeProgressData {
  node_id: string;
  node_type: string | null;
  status: 'pending' | 'running' | 'completed' | 'error';
  current_step: number | null;
  total_steps: number | null;
  percentage: number;
}

export interface ExecutionProgress {
  job_id: string;
  graph_progress: GraphProgressData;
  node_progress: NodeProgressData;
}

export interface StepProgress {
  job_id: string;
  node_id: string;
  current_step: number;
  total_steps: number;
  percentage: number;
  phase?: 'loading' | 'inference';
}

/** Output data from a single node execution */
export interface NodeExecutionOutput {
  preview?: string;
  before_url?: string;
  after_url?: string;
  [key: string]: unknown;
}

export interface ExecutionComplete {
  job_id: string;
  outputs: Record<string, NodeExecutionOutput>;
}

export interface ExecutionError {
  job_id: string;
  node_id: string;
  error: string;
}
