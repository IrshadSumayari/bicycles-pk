import { Input } from "@/components/ui/input";
import {
  useInfiniteProducts,
  useProductCategories,
} from "../../lib/hooks/useProducts";
import { useCoverImages } from "../../lib/hooks/useCoverImages";
import { productsService, type ProductSort } from "../../lib/services";
import { getErrorMessage } from "../../lib/errors";
import { swalConfig } from "../../lib/sweetAlert";
import { scannerCode } from "../../lib/productSearch";
import { ReportStatus } from "../reports/ReportStatus";
import { useState, useRef, useEffect, useMemo } from "react";
import {
  Search,
  Plus,
  Package,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";
import { Product, productLabel } from "../../types";
import { useApp } from "../../context/SupabaseAppContext";
interface ProductGridProps {
  onAddToCart: (product: Product) => void;
}
export function ProductGrid({ onAddToCart }: ProductGridProps) {
  const { state } = useApp();
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedCategory, setSelectedCategory] = useState("All");
  const categoriesRef = useRef<HTMLDivElement>(null);
  const [showLeftScroll, setShowLeftScroll] = useState(false);
  const [showRightScroll, setShowRightScroll] = useState(false);
  const [sort, setSort] = useState<ProductSort>("updated");
  const query = useInfiniteProducts({
    q: searchTerm,
    category: selectedCategory === "All" ? undefined : selectedCategory,
    sort,
  });
  const categoryQuery = useProductCategories();
  const filteredProducts = query.data?.pages.flatMap((page) => page.rows) ?? [];
  const coverImage = useCoverImages(filteredProducts);
  const categories = useMemo(
    () => ["All", ...(categoryQuery.data ?? [])],
    [categoryQuery.data],
  );
  useEffect(() => {
    if (categoryQuery.isSuccess && !categories.includes(selectedCategory)) setSelectedCategory('All');
  }, [categoryQuery.isSuccess, categories, selectedCategory]);
  const [scanning, setScanning] = useState(false);
  const isTouchMode = state.settings.interfaceMode === "touch";
  const checkScrollButtons = () => {
    if (categoriesRef.current) {
      const { scrollLeft, scrollWidth, clientWidth } = categoriesRef.current;
      setShowLeftScroll(scrollLeft > 0);
      setShowRightScroll(scrollLeft < scrollWidth - clientWidth - 5); // 5px tolerance
    }
  };
  useEffect(() => {
    checkScrollButtons();
    const categoriesElement = categoriesRef.current;
    if (categoriesElement) {
      categoriesElement.addEventListener("scroll", checkScrollButtons);
      return () =>
        categoriesElement.removeEventListener("scroll", checkScrollButtons);
    }
  }, [categories]);
  const scrollCategories = (direction: "left" | "right") => {
    if (categoriesRef.current) {
      const scrollAmount = 200;
      const currentScroll = categoriesRef.current.scrollLeft;
      const targetScroll =
        direction === "left"
          ? currentScroll - scrollAmount
          : currentScroll + scrollAmount;
      categoriesRef.current.scrollTo({
        left: targetScroll,
        behavior: "smooth",
      });
    }
  };
  return (
    <>
      <div className="card flex-1 min-w-0 min-h-0 flex flex-col h-full">
        {/* Search and Filter Bar */}
        <div className="p-4 lg:p-6 border-b border-border bg-card">
          <div className="flex flex-col lg:flex-row gap-4">
            <div className="relative flex-1 lg:min-w-[260px]">
              <Search className="absolute left-4 top-1/2 transform -translate-y-1/2 text-bodytext h-5 w-5" />
              <Input
                type="text"
                placeholder="Search name, SKU or barcode"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                onKeyDown={async (event) => {
                  const code = scannerCode(
                    event.currentTarget.value,
                    event.key,
                    event.nativeEvent.isComposing,
                  );
                  if (!code) return;
                  event.preventDefault();
                  setScanning(true);
                  try {
                    const product = await productsService.byCode(code);
                    if (product) {
                      setSearchTerm("");
                      if (product.trackInventory && product.stock <= 0)
                        swalConfig.warning("This item is out of stock");
                      else onAddToCart(product);
                    }
                  } catch (error) {
                    swalConfig.error(getErrorMessage(error));
                  } finally {
                    setScanning(false);
                  }
                }}
                className={`input pl-12 ${isTouchMode ? "h-14 text-lg" : "h-12"}`}
              />
            </div>
            <select
              aria-label="Sort products"
              value={sort}
              onChange={(e) => setSort(e.target.value as ProductSort)}
              className={`select lg:w-48 ${isTouchMode ? "h-14 text-lg" : "h-12"}`}
            >
              <option value="updated">Recently updated</option>
              <option value="newest">Newest added</option>
              <option value="name">Name A-Z</option>
            </select>
            <div className="relative flex items-center">
              {/* Left scroll button */}
              {showLeftScroll && (
                <button
                  onClick={() => scrollCategories("left")}
                  className="absolute left-0 z-10 flex items-center justify-center w-8 h-8 bg-card border border-border rounded-full shadow-xs hover:bg-lightgray transition-all"
                  style={{ transform: "translateX(-50%)" }}
                >
                  <ChevronLeft className="h-4 w-4 text-bodytext" />
                </button>
              )}
              {/* Categories container */}
              <div
                ref={categoriesRef}
                className="flex overflow-x-auto space-x-2 lg:space-x-3 max-w-xl scrollbar-hide scroll-smooth px-6"
                style={{ scrollbarWidth: "none", msOverflowStyle: "none" }}
              >
                {categories.map((category) => (
                  <button
                    key={category}
                    onClick={() => setSelectedCategory(category)}
                    className={`btn whitespace-nowrap transition-all flex-shrink-0 ${
                      selectedCategory === category
                        ? "btn-primary"
                        : "btn-secondary"
                    } ${isTouchMode ? "btn-lg touch-friendly" : "btn-md"}`}
                    title={category}
                  >
                    {category.split(">").pop()?.trim() || category}
                  </button>
                ))}
              </div>
              {/* Right scroll button */}
              {showRightScroll && (
                <button
                  onClick={() => scrollCategories("right")}
                  className="absolute right-0 z-10 flex items-center justify-center w-8 h-8 bg-card border border-border rounded-full shadow-xs hover:bg-lightgray transition-all"
                  style={{ transform: "translateX(50%)" }}
                >
                  <ChevronRight className="h-4 w-4 text-bodytext" />
                </button>
              )}
            </div>
          </div>
        </div>
        {/* Product Grid */}
        <div className="flex-1 min-h-0 p-4 lg:p-6 overflow-auto">
          <ReportStatus
            loading={query.isPending}
            error={query.error ?? categoryQuery.error}
            retry={() => {
              void query.refetch();
              void categoryQuery.refetch();
            }}
          />
          {(scanning || query.searching) && (
            <p role="status" className="text-sm text-bodytext mb-3">
              {scanning ? "Looking up code…" : "Searching products…"}
            </p>
          )}
          {filteredProducts.length === 0 && !query.isPending ? (
            <div className="flex flex-col items-center justify-center h-64">
              <div className="bg-lightgray p-6 rounded-3xl mb-4">
                <Package className="h-16 w-16 text-bodytext" />
              </div>
              <p className="text-bodytext text-lg font-medium">
                No products found
              </p>
              <p className="text-bodytext text-sm mt-1">
                Try adjusting your search or filters
              </p>
            </div>
          ) : (
            <div
              className={`product-catalog-grid grid gap-4 lg:gap-6 ${
                isTouchMode
                  ? "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
                  : "grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6"
              }`}
            >
              {filteredProducts.map((product) => (
                <ProductCard
                  key={product.id}
                  product={product}
                  image={coverImage(product)}
                  onAddToCart={onAddToCart}
                  isTouchMode={isTouchMode}
                  currency={state.settings.currency}
                />
              ))}
            </div>
          )}
          {query.hasNextPage && (
            <button
              type="button"
              className="btn btn-secondary btn-md mt-4"
              disabled={
                query.isFetchingNextPage ||
                query.isPlaceholderData ||
                query.searching
              }
              onClick={() => void query.fetchNextPage()}
            >
              Load more products
            </button>
          )}
          <p className="text-sm text-bodytext mt-3">
            Showing {filteredProducts.length} of{" "}
            {query.data?.pages[0]?.total ?? 0} products
          </p>
        </div>
      </div>
    </>
  );
}

interface ProductCardProps {
  product: Product;
  image?: string;
  onAddToCart: (product: Product) => void;
  isTouchMode: boolean;
  currency: string;
}
function ProductCard({
  product,
  image,
  onAddToCart,
  isTouchMode,
  currency,
}: ProductCardProps) {
  // Default to tracked when trackInventory is undefined (older rows).
  const shouldTrackInventory = product.trackInventory !== false;
  const isOutOfStock = shouldTrackInventory && product.stock <= 0;
  const isLowStock =
    shouldTrackInventory && !isOutOfStock && product.stock <= product.minStock;
  const options = [product.size, product.color, product.fit].filter(Boolean);
  const add = () => !isOutOfStock && onAddToCart(product);
  return (
    <div
      role="button"
      tabIndex={isOutOfStock ? -1 : 0}
      aria-disabled={isOutOfStock}
      aria-label={`Add ${productLabel(product)} to cart`}
      onClick={add}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          add();
        }
      }}
      className={`group flex flex-col overflow-hidden rounded-2xl border bg-card transition-all duration-150 focus-visible:outline-2 focus-visible:outline-primary ${
        isOutOfStock
          ? "border-border opacity-60 cursor-not-allowed"
          : "border-border cursor-pointer hover:border-primary hover:shadow-md"
      }`}
    >
      {/* Product image */}
      <div className="relative aspect-square bg-lightgray overflow-hidden">
        {image ? (
          <img
            src={image}
            alt=""
            loading="lazy"
            className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
          />
        ) : (
          <div className="h-full w-full flex items-center justify-center">
            <Package className="h-10 w-10 text-bodytext/60" />
          </div>
        )}
        {isOutOfStock && (
          <span className="absolute inset-x-0 bottom-0 bg-black/60 py-1.5 text-center text-xs font-semibold text-white">
            Out of stock
          </span>
        )}
        {isLowStock && (
          <span className="absolute left-2 top-2 rounded-full bg-warning px-2 py-0.5 text-[11px] font-semibold text-white">
            Only {product.stock} left
          </span>
        )}
        {!isOutOfStock && (
          <button
            type="button"
            aria-label={`Add ${productLabel(product)} to cart`}
            onClick={(event) => {
              event.stopPropagation();
              add();
            }}
            className={`absolute bottom-2 right-2 flex items-center justify-center rounded-full bg-primary text-white shadow-md transition-transform hover:scale-110 ${
              isTouchMode ? "h-11 w-11" : "h-9 w-9"
            }`}
          >
            <Plus className={isTouchMode ? "h-5 w-5" : "h-4 w-4"} />
          </button>
        )}
      </div>
      {/* Product info */}
      <div className={`flex flex-1 flex-col gap-1.5 ${isTouchMode ? "p-3" : "p-2.5"}`}>
        <h3
          className={`font-medium leading-snug text-link line-clamp-2 ${isTouchMode ? "text-sm" : "text-[13px]"}`}
          title={productLabel(product)}
        >
          {product.name}
        </h3>
        {options.length > 0 && (
          <div className="flex flex-wrap gap-1">
            {options.map((option) => (
              <span
                key={option}
                className="rounded-md bg-lightgray px-1.5 py-0.5 text-[11px] font-medium text-bodytext"
              >
                {option}
              </span>
            ))}
          </div>
        )}
        <div className="mt-auto flex items-end justify-between gap-2 pt-1">
          <span
            className={`font-semibold text-primary whitespace-nowrap ${isTouchMode ? "text-base" : "text-sm"}`}
          >
            {currency} {product.price.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 2 })}
          </span>
          <span
            className={`text-[11px] whitespace-nowrap ${isLowStock ? "text-warning font-medium" : "text-bodytext"}`}
          >
            {shouldTrackInventory ? `${product.stock} in stock` : "Unlimited"}
          </span>
        </div>
        <p className="text-[10px] text-bodytext/80 truncate font-mono" title={product.sku}>
          {product.sku}
        </p>
      </div>
    </div>
  );
}
