import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const inputVariants = cva(
  "flex h-10 w-full border rounded-lg px-3 py-2 text-sm disabled:cursor-not-allowed disabled:opacity-50 file:border-0 file:rounded-sm file:text-sm file:font-medium file:text-primary file:bg-lightprimary  focus-visible:outline-0",
  {
    variants: {
      variant: {
        default:
          "border-ld bg-transparent text-ld placeholder:text-bodytext dark:placeholder:text-white/30 focus-visible:border-primary focus-visible:ring-0",
        gray: "border-border bg-lightgray text-link placeholder-bodytext focus:border-primary-500 focus:ring-primary-500 dark:border-border dark:bg-darkgray dark:text-white dark:placeholder-bodytext dark:focus:border-primary-500 dark:focus:ring-primary-500 focus-visible:ring",
        info: "border-secondary bg-lightsecondary text-secondary placeholder-secondary focus:border-secondary focus:ring-secondary dark:border-secondary dark:bg-lightsecondary dark:focus:border-secondary dark:focus:ring-secondary focus-visible:ring",
        failure:
          "border-error bg-lighterror text-error placeholder-error focus:border-error focus:ring-error dark:border-error dark:bg-lighterror dark:focus:border-error dark:focus:ring-error focus-visible:ring",
        warning:
          "border-warning bg-lightwarning text-warning placeholder-warning focus:border-warning focus:ring-warning dark:border-warning dark:bg-lightwarning dark:focus:border-warning dark:focus:ring-warning focus-visible:ring",
        success:
          "border-success bg-lightsuccess text-success placeholder-success focus:border-success focus:ring-success dark:border-success dark:bg-lightsuccess dark:focus:border-success dark:focus:ring-success focus-visible:ring",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
);

export interface InputProps
  extends
    React.InputHTMLAttributes<HTMLInputElement>,
    VariantProps<typeof inputVariants> {}

const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, type = "text", variant, ...props }, ref) => {
    // Checkboxes and radios must not take the full-width text-field sizing.
    if (type === "checkbox" || type === "radio")
      return (
        <input
          type={type}
          className={cn(
            "h-4 w-4 shrink-0 cursor-pointer rounded border-border accent-primary disabled:cursor-not-allowed disabled:opacity-50",
            className,
          )}
          ref={ref}
          {...props}
        />
      );
    return (
      <input
        type={type}
        className={cn(inputVariants({ variant }), className)}
        ref={ref}
        {...props}
      />
    );
  },
);

Input.displayName = "Input";

export { Input };
