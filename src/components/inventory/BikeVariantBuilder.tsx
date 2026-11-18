import { bikeColours, categorySizes, sectionOfCategory } from "../../../shared/bicycles";
// Size and colour shortcuts for the chosen shop category: frame sizes for
// bikes, wheel sizes for kids bikes and tyres, One size for most accessories.
export function BikeVariantBuilder({
  category,
  onSizes,
  onColours,
}: {
  category: string;
  onSizes: (sizes: string[]) => void;
  onColours: (values: string[]) => void;
}) {
  const sizes = categorySizes(category);
  const section = sectionOfCategory(category);
  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-4">
      <h3 className="font-semibold text-link">{section?.label ?? "Shop"} options</h3>
      {sizes.length > 0 && (
        <div>
          <p className="text-sm font-medium mb-2">Size shortcuts</p>
          <div className="flex flex-wrap gap-2">
            {sizes.map((size) => (
              <button type="button" className="btn btn-secondary btn-sm" key={size} onClick={() => onSizes([size])}>
                Add {size}
              </button>
            ))}
          </div>
        </div>
      )}
      <div>
        <p className="text-sm font-medium mb-2">Colour shortcuts</p>
        <div className="flex flex-wrap gap-2">
          {bikeColours.map((colour) => (
            <button type="button" className="btn btn-secondary btn-sm" key={colour} onClick={() => onColours([colour])}>
              Add {colour}
            </button>
          ))}
        </div>
      </div>
      <p className="text-sm text-bodytext">
        Use one row per frame or wheel size and colour you stock. Bike specifications
        (gears, brakes, weight, rider height) go in the Website tab.
      </p>
    </div>
  );
}
