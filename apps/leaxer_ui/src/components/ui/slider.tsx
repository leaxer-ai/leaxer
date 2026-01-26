"use client"

import * as React from "react"
import * as SliderPrimitive from "@radix-ui/react-slider"
import { cn } from "@/lib/utils"

type AccentColor = 'accent' | 'success' | 'warning' | 'error' | 'info';

interface SliderProps extends Omit<React.ComponentProps<typeof SliderPrimitive.Root>, 'value' | 'onValueChange' | 'onChange'> {
  value?: number;
  onChange?: (value: number) => void;
  min?: number;
  max?: number;
  step?: number;
  color?: AccentColor;
  showValue?: boolean;
}

function Slider({
  className,
  value,
  onChange,
  min = 0,
  max = 100,
  step = 1,
  color = 'accent',
  showValue = false,
  disabled,
  ...props
}: SliderProps) {
  const sliderValue = value !== undefined ? [value] : [min];

  const handleValueChange = (values: number[]) => {
    if (onChange && values[0] !== undefined) {
      onChange(values[0]);
    }
  };

  return (
    <div className={cn("flex items-center gap-3", className)}>
      <SliderPrimitive.Root
        data-slot="slider"
        value={sliderValue}
        onValueChange={handleValueChange}
        min={min}
        max={max}
        step={step}
        disabled={disabled}
        className={cn(
          "relative flex w-full touch-none items-center select-none",
          "data-[disabled]:opacity-50 data-[disabled]:cursor-not-allowed",
          "group"
        )}
        {...props}
      >
        {/* Track: surface-2 background, 4px height, rounded */}
        <SliderPrimitive.Track
          data-slot="slider-track"
          className={cn(
            "relative h-1 w-full grow overflow-hidden rounded-full",
            "bg-surface-2 group-hover:bg-overlay-0 transition-colors"
          )}
        >
          {/* Fill: Theme-adaptive color */}
          <SliderPrimitive.Range
            data-slot="slider-range"
            className="absolute h-full"
            style={{ backgroundColor: `var(--color-${color})` }}
          />
        </SliderPrimitive.Track>

        {/* Thumb: 14px circle, text color for visibility */}
        <SliderPrimitive.Thumb
          data-slot="slider-thumb"
          className={cn(
            "block h-3.5 w-3.5 shrink-0 rounded-full",
            "bg-text border-none",
            "shadow-md",
            "transition-all duration-150",
            "hover:scale-110",
            "active:bg-accent active:scale-115",
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/30",
            "disabled:pointer-events-none disabled:opacity-50 disabled:bg-text-muted"
          )}
        />
      </SliderPrimitive.Root>

      {/* Optional value display */}
      {showValue && (
        <span className="min-w-[3ch] text-xs font-medium text-text-secondary tabular-nums text-right">
          {value ?? min}
        </span>
      )}
    </div>
  )
}

export { Slider }
export type { SliderProps, AccentColor }
