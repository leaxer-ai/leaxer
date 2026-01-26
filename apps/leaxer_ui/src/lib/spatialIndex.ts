/**
 * Grid-based spatial index for O(1) average-case point-in-rectangle queries.
 *
 * Used by NodeGraph to efficiently find which group(s) contain a given point
 * during drag operations, avoiding O(N) iteration over all groups.
 *
 * Design:
 * - Canvas is divided into a grid of cells (default 200x200 pixels)
 * - Each rectangle is stored in all cells it overlaps
 * - Point queries only check rectangles in the containing cell
 *
 * Complexity:
 * - Build: O(R * C) where R = rectangles, C = avg cells per rectangle
 * - Query: O(K) where K = avg rectangles per cell (typically << N)
 */

export interface Rectangle {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

interface GridCell {
  rectangles: Rectangle[];
}

export class SpatialIndex {
  private cellSize: number;
  private grid: Map<string, GridCell> = new Map();
  private rectangles: Map<string, Rectangle> = new Map();

  constructor(cellSize: number = 200) {
    this.cellSize = cellSize;
  }

  /**
   * Build index from an array of rectangles.
   * Clears any existing data.
   */
  build(rectangles: Rectangle[]): void {
    this.grid.clear();
    this.rectangles.clear();

    for (const rect of rectangles) {
      this.insert(rect);
    }
  }

  /**
   * Insert a single rectangle into the index.
   */
  insert(rect: Rectangle): void {
    this.rectangles.set(rect.id, rect);

    // Calculate which grid cells this rectangle overlaps
    const minCellX = Math.floor(rect.x / this.cellSize);
    const minCellY = Math.floor(rect.y / this.cellSize);
    const maxCellX = Math.floor((rect.x + rect.width) / this.cellSize);
    const maxCellY = Math.floor((rect.y + rect.height) / this.cellSize);

    for (let cellX = minCellX; cellX <= maxCellX; cellX++) {
      for (let cellY = minCellY; cellY <= maxCellY; cellY++) {
        const key = `${cellX},${cellY}`;
        let cell = this.grid.get(key);
        if (!cell) {
          cell = { rectangles: [] };
          this.grid.set(key, cell);
        }
        cell.rectangles.push(rect);
      }
    }
  }

  /**
   * Find the first rectangle containing the given point.
   * Returns null if no rectangle contains the point.
   *
   * @param x - X coordinate of the point
   * @param y - Y coordinate of the point
   * @param exclude - Optional ID to skip (e.g., the node's current parent)
   */
  findContaining(x: number, y: number, exclude?: string): Rectangle | null {
    const cellX = Math.floor(x / this.cellSize);
    const cellY = Math.floor(y / this.cellSize);
    const key = `${cellX},${cellY}`;

    const cell = this.grid.get(key);
    if (!cell) return null;

    for (const rect of cell.rectangles) {
      if (exclude && rect.id === exclude) continue;

      if (
        x >= rect.x &&
        x <= rect.x + rect.width &&
        y >= rect.y &&
        y <= rect.y + rect.height
      ) {
        return rect;
      }
    }

    return null;
  }

  /**
   * Find all rectangles containing the given point.
   *
   * @param x - X coordinate of the point
   * @param y - Y coordinate of the point
   * @param exclude - Optional ID to skip
   */
  findAllContaining(x: number, y: number, exclude?: string): Rectangle[] {
    const cellX = Math.floor(x / this.cellSize);
    const cellY = Math.floor(y / this.cellSize);
    const key = `${cellX},${cellY}`;

    const cell = this.grid.get(key);
    if (!cell) return [];

    return cell.rectangles.filter((rect) => {
      if (exclude && rect.id === exclude) return false;

      return (
        x >= rect.x &&
        x <= rect.x + rect.width &&
        y >= rect.y &&
        y <= rect.y + rect.height
      );
    });
  }

  /**
   * Get a rectangle by ID.
   */
  get(id: string): Rectangle | undefined {
    return this.rectangles.get(id);
  }

  /**
   * Check if the index is empty.
   */
  isEmpty(): boolean {
    return this.rectangles.size === 0;
  }

  /**
   * Get the number of rectangles in the index.
   */
  get size(): number {
    return this.rectangles.size;
  }
}

/**
 * Create a spatial index from an array of rectangles.
 * Convenience function for one-liner usage.
 */
export function createSpatialIndex(
  rectangles: Rectangle[],
  cellSize?: number
): SpatialIndex {
  const index = new SpatialIndex(cellSize);
  index.build(rectangles);
  return index;
}
