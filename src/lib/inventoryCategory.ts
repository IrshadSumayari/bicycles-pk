import { shopSections, type SectionId } from '../../shared/bicycles';

export const ALL_CATEGORIES = 'All';
export type Department = SectionId;

const departments = Object.fromEntries(
  shopSections.map(s => [s.id, { all: `All ${s.label.toLowerCase()}`, names: s.categories.map(c => c.name) }]),
) as Record<Department, { all: string; names: string[] }>;

export function allDepartmentCategory(department: Department | undefined): string {
  return department ? departments[department].all : ALL_CATEGORIES;
}

// The categories a department section lists; a style saved under any other
// category is not shown there.
export function departmentCategories(department: Department): string[] {
  return departments[department].names;
}

// New styles added from a section start in the chosen category, or the
// section's general one (Bicycles, Accessories...) when "All ..." is selected.
export function newStyleCategory(department: Department | undefined, selected: string): string | undefined {
  if (!department) return undefined;
  return departments[department].names.includes(selected) ? selected : departments[department].names[0];
}

// Category choices for the Inventory section or a shop section
export function inventoryCategoryOptions(department: Department | undefined, categories: string[]): string[] {
  return department
    ? [departments[department].all, ...departments[department].names]
    : [ALL_CATEGORIES, ...categories];
}

// The search filter for a selection: every category of a section, one exact category, or none
export function inventoryCategoryFilter(selected: string): { category?: string; categories?: string[] } {
  for (const d of Object.values(departments)) if (selected === d.all) return { categories: d.names };
  return selected === ALL_CATEGORIES ? {} : { category: selected };
}
