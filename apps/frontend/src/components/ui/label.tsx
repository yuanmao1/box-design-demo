import * as LabelPrimitive from '@radix-ui/react-label'
import { cva } from 'class-variance-authority'
import type * as React from 'react'
import { cn } from '@/lib/utils'

const labelVariants = cva('text-sm font-medium text-foreground leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70')

const Label = ({ className, ...props }: React.ComponentProps<typeof LabelPrimitive.Root>) => (
  <LabelPrimitive.Root className={cn(labelVariants(), className)} {...props} />
)

export { Label }
