// Shop sections and their categories. Categories are stored on styles by
// exact name, so POS sections and storefront links use the same filter.
// The first category of each section is its general one.
export type SectionId =
  | "bicycles"
  | "kids"
  | "sports"
  | "ebikes"
  | "accessories"
  | "parts";

export type ShopCategory = {
  name: string;
  slug: string;
  description: string;
  sizes: readonly string[];
};

export type ShopSection = {
  id: SectionId;
  label: string;
  href: string;
  description: string;
  categories: readonly ShopCategory[];
};

const frame = ["XS", "S", "M", "L", "XL"] as const;
const roadFrame = ["47 cm", "49 cm", "52 cm", "54 cm", "56 cm", "58 cm", "61 cm"] as const;
const kidsWheel = ['12"', '14"', '16"', '20"', '24"'] as const;
const oneSize = ["One size"] as const;

export const shopSections: readonly ShopSection[] = [
  {
    id: "bicycles",
    label: "Bicycles",
    href: "/bicycles",
    description: "Everyday bikes for the city, the commute and the weekend.",
    categories: [
      { name: "Bicycles", slug: "bicycles", description: "Every everyday ride.", sizes: frame },
      { name: "City & Commuter", slug: "city-commuter", description: "Upright, practical and ready for daily trips.", sizes: frame },
      { name: "Hybrid Bikes", slug: "hybrid-bikes", description: "Quick on roads, happy on light trails.", sizes: frame },
      { name: "Folding Bikes", slug: "folding-bikes", description: "Fold, carry and store with ease.", sizes: ['16"', '20"', "One size"] },
      { name: "Cruisers", slug: "cruisers", description: "Relaxed comfort for easy rides.", sizes: ['24"', '26"', "One size"] },
      { name: "Women's Bikes", slug: "womens-bikes", description: "Step-through frames and comfortable fits.", sizes: frame },
    ],
  },
  {
    id: "kids",
    label: "Kids",
    href: "/kids",
    description: "First pedals to first adventures, sized by wheel and age.",
    categories: [
      { name: "Kids Bicycles", slug: "kids-bicycles", description: "Bikes sized for every age.", sizes: kidsWheel },
      { name: "Balance Bikes", slug: "balance-bikes", description: "Learn to balance before pedalling.", sizes: ['10"', '12"'] },
      { name: "Training Wheel Bikes", slug: "training-wheel-bikes", description: "Steady support for first rides.", sizes: ['12"', '14"', '16"'] },
      { name: "Junior Bikes", slug: "junior-bikes", description: "Gears and bigger wheels for growing riders.", sizes: ['20"', '24"'] },
    ],
  },
  {
    id: "sports",
    label: "Sports",
    href: "/sports",
    description: "Road, mountain, gravel and BMX bikes built for performance.",
    categories: [
      { name: "Sports Bicycles", slug: "sports-bicycles", description: "Every performance bike.", sizes: frame },
      { name: "Road Bikes", slug: "road-bikes", description: "Light, fast and made for tarmac.", sizes: roadFrame },
      { name: "Mountain Bikes", slug: "mountain-bikes", description: "Suspension and grip for the trail.", sizes: frame },
      { name: "Gravel Bikes", slug: "gravel-bikes", description: "Wide tyres for any surface.", sizes: roadFrame },
      { name: "BMX", slug: "bmx", description: "Tough bikes for tricks and parks.", sizes: ['20"'] },
    ],
  },
  {
    id: "ebikes",
    label: "E-bikes",
    href: "/e-bikes",
    description: "Pedal assistance for longer, easier rides.",
    categories: [
      { name: "E-bikes", slug: "e-bikes", description: "Every electric bike.", sizes: frame },
      { name: "City E-bikes", slug: "city-e-bikes", description: "Arrive fresh, wherever you're going.", sizes: frame },
      { name: "Electric Mountain Bikes", slug: "electric-mountain-bikes", description: "Climb further on the trail.", sizes: frame },
      { name: "Folding E-bikes", slug: "folding-e-bikes", description: "Compact with electric assistance.", sizes: ['16"', '20"', "One size"] },
    ],
  },
  {
    id: "accessories",
    label: "Accessories",
    href: "/accessories",
    description: "Helmets, lights, locks and everything for the ride.",
    categories: [
      { name: "Accessories", slug: "accessories", description: "Everything for the ride.", sizes: oneSize },
      { name: "Helmets", slug: "helmets", description: "Protection that fits.", sizes: ["XS", "S", "M", "L"] },
      { name: "Lights", slug: "lights", description: "See and be seen.", sizes: oneSize },
      { name: "Locks", slug: "locks", description: "Keep your bike where you left it.", sizes: oneSize },
      { name: "Pumps", slug: "pumps", description: "Floor and mini pumps.", sizes: oneSize },
      { name: "Bottles & Cages", slug: "bottles-cages", description: "Stay hydrated on the move.", sizes: oneSize },
      { name: "Bags & Racks", slug: "bags-racks", description: "Carry more on your bike.", sizes: oneSize },
      { name: "Bells & Mirrors", slug: "bells-mirrors", description: "Safety for busy roads.", sizes: oneSize },
      { name: "Phone Mounts", slug: "phone-mounts", description: "Navigation at a glance.", sizes: oneSize },
    ],
  },
  {
    id: "parts",
    label: "Parts",
    href: "/parts",
    description: "Tyres, tubes and spares to keep you riding.",
    categories: [
      { name: "Parts", slug: "parts", description: "Every spare part.", sizes: oneSize },
      { name: "Tyres & Tubes", slug: "tyres-tubes", description: "Grip and puncture protection.", sizes: ['12"', '16"', '20"', '24"', '26"', '27.5"', '29"', "700c"] },
      { name: "Chains", slug: "chains", description: "Smooth, quiet shifting.", sizes: ["Single speed", "7/8 speed", "9 speed", "10 speed", "11 speed", "12 speed"] },
      { name: "Brakes & Pads", slug: "brakes-pads", description: "Confident stopping.", sizes: oneSize },
      { name: "Pedals", slug: "pedals", description: "Flat and clipless pedals.", sizes: oneSize },
      { name: "Saddles", slug: "saddles", description: "Comfort for every ride.", sizes: oneSize },
      { name: "Grips & Handlebars", slug: "grips-handlebars", description: "Control and comfort.", sizes: oneSize },
    ],
  },
];

export const bikeColours = [
  "Black",
  "White",
  "Grey",
  "Silver",
  "Red",
  "Blue",
  "Green",
  "Yellow",
  "Orange",
  "Pink",
];

const key = (value: string | undefined) => value?.trim().toLowerCase() ?? "";

export function sectionById(id: SectionId): ShopSection {
  return shopSections.find((s) => s.id === id)!;
}

export function sectionOfCategory(category: string | undefined): ShopSection | undefined {
  const value = key(category);
  return value ? shopSections.find((s) => s.categories.some((c) => key(c.name) === value)) : undefined;
}

export function categorySizes(category: string): readonly string[] {
  const value = key(category);
  for (const s of shopSections)
    for (const c of s.categories) if (key(c.name) === value) return c.sizes;
  return [];
}

export function shopCategoryNames(): string[] {
  return shopSections.flatMap((s) => s.categories.map((c) => c.name));
}

export function categoryHref(category: string): string {
  return "/search?category=" + encodeURIComponent(category);
}
