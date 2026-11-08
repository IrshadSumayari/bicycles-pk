import { jewelleryCategories } from '../../shared/jewellery';
import { bagCategories } from '../../shared/bags';

export const ALL_CATEGORIES = 'All';
export const ALL_JEWELLERY = 'All jewellery';
export const ALL_BAGS = 'All bags';
export type Department = 'jewellery' | 'bags';

const departments = {
  jewellery: { all: ALL_JEWELLERY, names: jewelleryCategories.map(c => c.name) as string[] },
  bags: { all: ALL_BAGS, names: bagCategories.map(c => c.name) as string[] },
} satisfies Record<Department, { all: string; names: string[] }>;

export function allDepartmentCategory(department: Department | undefined): string {
  return department ? departments[department].all : ALL_CATEGORIES;
}

// The categories a department section lists; a style saved under any other
// category is not shown there.
export function departmentCategories(department: Department): string[] {
  return departments[department].names;
}

// New styles added from a department start in the chosen category, or the
// department's general one (Bags, Jewellery) when "All ..." is selected.
export function newStyleCategory(department: Department | undefined, selected: string): string | undefined {
  if (!department) return undefined;
  return departments[department].names.includes(selected) ? selected : departments[department].names[0];
}

// Category choices for the Inventory section or a department section (Jewellery, Bags)
export function inventoryCategoryOptions(department: Department | undefined, categories: string[]): string[] {
  return department
    ? [departments[department].all, ...departments[department].names]
    : [ALL_CATEGORIES, ...categories];
}

// The search filter for a selection: every category of a department, one exact category, or none
export function inventoryCategoryFilter(selected: string): { category?: string; categories?: string[] } {
  for (const d of Object.values(departments)) if (selected === d.all) return { categories: d.names };
  return selected === ALL_CATEGORIES ? {} : { category: selected };
}
