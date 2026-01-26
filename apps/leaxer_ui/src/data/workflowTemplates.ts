import type { Node, Edge } from '@xyflow/react';

export interface WorkflowTemplate {
  id: string;
  name: string;
  description: string;
  nodes: Node[];
  edges: Edge[];
}

export const workflowTemplates: WorkflowTemplate[] = [
  {
    id: 'text-to-image',
    name: 'Text to Image',
    description: 'Generate images from text prompts',
    nodes: [
      {
        id: 'node_0',
        type: 'LoadModel',
        position: { x: 50, y: 50 },
        data: {},
      },
      {
        id: 'node_1',
        type: 'GenerateImage',
        position: { x: 350, y: 50 },
        data: { prompt: 'a photo of a cat, detailed, 4k, professional photography', negative_prompt: 'blurry, bad quality, distorted', steps: 20, cfg_scale: 7.5, width: 512, height: 512, seed: -1 },
      },
      {
        id: 'node_2',
        type: 'SaveImage',
        position: { x: 650, y: 50 },
        data: { filename: 'output' },
      },
      {
        id: 'node_3',
        type: 'PreviewImage',
        position: { x: 650, y: 200 },
        data: {},
      },
    ],
    edges: [
      { id: 'e0-1', source: 'node_0', sourceHandle: 'model', target: 'node_1', targetHandle: 'model', type: 'colored', data: { dataType: 'MODEL' } },
      { id: 'e1-2', source: 'node_1', sourceHandle: 'image', target: 'node_2', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e1-3', source: 'node_1', sourceHandle: 'image', target: 'node_3', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
    ],
  },
  {
    id: 'face-detailer',
    name: 'Face Detailer',
    description: 'Detect and enhance faces in images',
    nodes: [
      {
        id: 'node_0',
        type: 'LoadImage',
        position: { x: 50, y: 150 },
        data: {},
      },
      {
        id: 'node_1',
        type: 'GroundingDinoLoader',
        position: { x: 50, y: 350 },
        data: {},
      },
      {
        id: 'node_2',
        type: 'DetectObjects',
        position: { x: 300, y: 150 },
        data: { prompt: 'face', box_threshold: 0.35, text_threshold: 0.25 },
      },
      {
        id: 'node_3',
        type: 'SAMLoader',
        position: { x: 300, y: 400 },
        data: { model_name: 'mobile_sam' },
      },
      {
        id: 'node_4',
        type: 'SAMSegment',
        position: { x: 550, y: 200 },
        data: {},
      },
      {
        id: 'node_5',
        type: 'SEGSPreview',
        position: { x: 550, y: 400 },
        data: {},
      },
      {
        id: 'node_6',
        type: 'LoadModel',
        position: { x: 550, y: 550 },
        data: {},
      },
      {
        id: 'node_7',
        type: 'DetailerForEach',
        position: { x: 800, y: 150 },
        data: {
          positive: 'highly detailed face, sharp focus, beautiful skin',
          negative: 'blurry, distorted, ugly',
          denoise: 0.4,
          steps: 20,
          cfg: 7.0
        },
      },
      {
        id: 'node_8',
        type: 'PreviewImage',
        position: { x: 1100, y: 150 },
        data: {},
      },
      {
        id: 'node_9',
        type: 'SaveImage',
        position: { x: 1100, y: 350 },
        data: { filename: 'face_detailed' },
      },
    ],
    edges: [
      { id: 'e0-2', source: 'node_0', sourceHandle: 'image', target: 'node_2', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e1-2', source: 'node_1', sourceHandle: 'detector', target: 'node_2', targetHandle: 'detector', type: 'colored', data: { dataType: 'DETECTOR' } },
      { id: 'e2-4', source: 'node_2', sourceHandle: 'segs', target: 'node_4', targetHandle: 'segs', type: 'colored', data: { dataType: 'SEGS' } },
      { id: 'e0-4', source: 'node_0', sourceHandle: 'image', target: 'node_4', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e3-4', source: 'node_3', sourceHandle: 'sam_model', target: 'node_4', targetHandle: 'sam_model', type: 'colored', data: { dataType: 'SAM_MODEL' } },
      { id: 'e0-5', source: 'node_0', sourceHandle: 'image', target: 'node_5', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e4-5', source: 'node_4', sourceHandle: 'segs', target: 'node_5', targetHandle: 'segs', type: 'colored', data: { dataType: 'SEGS' } },
      { id: 'e0-7', source: 'node_0', sourceHandle: 'image', target: 'node_7', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e4-7', source: 'node_4', sourceHandle: 'segs', target: 'node_7', targetHandle: 'segs', type: 'colored', data: { dataType: 'SEGS' } },
      { id: 'e6-7', source: 'node_6', sourceHandle: 'model', target: 'node_7', targetHandle: 'model', type: 'colored', data: { dataType: 'MODEL' } },
      { id: 'e7-8', source: 'node_7', sourceHandle: 'image', target: 'node_8', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e7-9', source: 'node_7', sourceHandle: 'image', target: 'node_9', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
    ],
  },
  {
    id: 'hand-detailer',
    name: 'Hand Detailer',
    description: 'Detect and fix hands in images',
    nodes: [
      {
        id: 'node_0',
        type: 'LoadImage',
        position: { x: 50, y: 150 },
        data: {},
      },
      {
        id: 'node_1',
        type: 'GroundingDinoLoader',
        position: { x: 50, y: 350 },
        data: {},
      },
      {
        id: 'node_2',
        type: 'DetectObjects',
        position: { x: 300, y: 150 },
        data: { prompt: 'hand', box_threshold: 0.3, text_threshold: 0.25 },
      },
      {
        id: 'node_3',
        type: 'SAMLoader',
        position: { x: 300, y: 400 },
        data: { model_name: 'mobile_sam' },
      },
      {
        id: 'node_4',
        type: 'SAMSegment',
        position: { x: 550, y: 200 },
        data: {},
      },
      {
        id: 'node_5',
        type: 'SEGSPreview',
        position: { x: 550, y: 400 },
        data: {},
      },
      {
        id: 'node_6',
        type: 'LoadModel',
        position: { x: 550, y: 550 },
        data: {},
      },
      {
        id: 'node_7',
        type: 'DetailerForEach',
        position: { x: 800, y: 150 },
        data: {
          positive: 'detailed hand, correct fingers, natural pose, anatomically correct',
          negative: 'deformed, extra fingers, missing fingers, fused fingers, bad anatomy',
          denoise: 0.5,
          steps: 25,
          cfg: 7.5
        },
      },
      {
        id: 'node_8',
        type: 'PreviewImage',
        position: { x: 1100, y: 150 },
        data: {},
      },
      {
        id: 'node_9',
        type: 'SaveImage',
        position: { x: 1100, y: 350 },
        data: { filename: 'hand_fixed' },
      },
    ],
    edges: [
      { id: 'e0-2', source: 'node_0', sourceHandle: 'image', target: 'node_2', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e1-2', source: 'node_1', sourceHandle: 'detector', target: 'node_2', targetHandle: 'detector', type: 'colored', data: { dataType: 'DETECTOR' } },
      { id: 'e2-4', source: 'node_2', sourceHandle: 'segs', target: 'node_4', targetHandle: 'segs', type: 'colored', data: { dataType: 'SEGS' } },
      { id: 'e0-4', source: 'node_0', sourceHandle: 'image', target: 'node_4', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e3-4', source: 'node_3', sourceHandle: 'sam_model', target: 'node_4', targetHandle: 'sam_model', type: 'colored', data: { dataType: 'SAM_MODEL' } },
      { id: 'e0-5', source: 'node_0', sourceHandle: 'image', target: 'node_5', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e4-5', source: 'node_4', sourceHandle: 'segs', target: 'node_5', targetHandle: 'segs', type: 'colored', data: { dataType: 'SEGS' } },
      { id: 'e0-7', source: 'node_0', sourceHandle: 'image', target: 'node_7', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e4-7', source: 'node_4', sourceHandle: 'segs', target: 'node_7', targetHandle: 'segs', type: 'colored', data: { dataType: 'SEGS' } },
      { id: 'e6-7', source: 'node_6', sourceHandle: 'model', target: 'node_7', targetHandle: 'model', type: 'colored', data: { dataType: 'MODEL' } },
      { id: 'e7-8', source: 'node_7', sourceHandle: 'image', target: 'node_8', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
      { id: 'e7-9', source: 'node_7', sourceHandle: 'image', target: 'node_9', targetHandle: 'image', type: 'colored', data: { dataType: 'IMAGE' } },
    ],
  },
  {
    id: 'empty',
    name: 'Empty Workflow',
    description: 'Start with a blank canvas',
    nodes: [],
    edges: [],
  },
];

export function getTemplate(id: string): WorkflowTemplate | undefined {
  return workflowTemplates.find((t) => t.id === id);
}
