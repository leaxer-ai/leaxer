/**
 * Detailer Node Components
 *
 * These nodes use the auto-generated UI from NodeFactory based on their
 * backend specs. No custom components are needed unless specific UI
 * requirements emerge.
 *
 * Node Types:
 * - GroundingDinoLoader: Load GroundingDINO model for detection
 * - DetectObjects: Detect objects using text prompts
 * - SAMLoader: Load SAM model for segmentation
 * - SAMSegment: Create pixel masks from detections
 * - SEGSPreview: Visualize detected segments
 * - SEGSFilter: Filter segments by criteria
 * - SEGSToMask: Convert segments to mask image
 * - MaskToSEGS: Convert mask to segments
 * - SEGSCombine: Combine multiple segment sets
 * - DetailerForEach: Enhance each detected region
 *
 * Data Types:
 * - segs: Collection of segments (bbox + mask + label)
 * - detector: Loaded GroundingDINO model
 * - sam_model: Loaded SAM model
 */

// Export any custom components here if created later
export {};
