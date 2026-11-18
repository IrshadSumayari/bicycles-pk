import { Sale } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { useAuth } from '../../context/AuthContext';
import { format } from 'date-fns';

interface ReceiptPrintProps {
  sale: Sale;
  onClose: () => void;
}

export function ReceiptPrint({ sale, onClose }: ReceiptPrintProps) {
  const { state } = useApp();
  const { profile } = useAuth();

  const handlePrint = () => {
    window.print();
  };

  return (
    <div className="modal-overlay">
      <div className="modal max-w-md">
        <div className="modal-header no-print">
          <h2 className="text-xl font-bold text-link">Print Receipt</h2>
          <button
            onClick={onClose}
            className="text-bodytext hover:text-bodytext p-2 rounded-lg hover:bg-lightgray"
          >
            ×
          </button>
        </div>

        {/* Receipt Content */}
        <div className="modal-body" id="receipt-content">
          <div className="text-center mb-6">
            {state.settings.storeLogo && (
              <img 
                src={state.settings.storeLogo} 
                alt="Store Logo" 
                className="h-16 w-16 mx-auto mb-4 object-contain"
              />
            )}
            <h1 className="text-xl font-bold text-link">{state.settings.storeName}</h1>
            <p className="text-sm text-bodytext">{state.settings.storeAddress}</p>
            {state.settings.storePhone && (
              <p className="text-sm text-bodytext">Tel: {state.settings.storePhone}</p>
            )}
            {state.settings.storeEmail && (
              <p className="text-sm text-bodytext">Email: {state.settings.storeEmail}</p>
            )}
          </div>

          {state.settings.receiptHeader && <p className="text-center text-sm whitespace-pre-wrap mb-4">{state.settings.receiptHeader}</p>}
          {state.settings.ntn && <p className="text-sm">NTN: {state.settings.ntn}</p>}
          {state.settings.strn && <p className="text-sm mb-3">STRN: {state.settings.strn}</p>}
          <div className="border-t border-b border-border py-4 mb-4">
            <div className="flex justify-between text-sm mb-2">
              <span>Receipt #:</span>
              <span className="font-semibold">#{sale.receiptNumber}</span>
            </div>
            <div className="flex justify-between text-sm mb-2">
              <span>Invoice #:</span>
              <span className="font-semibold">{sale.invoiceNumber}</span>
            </div>
            <div className="flex justify-between text-sm mb-2">
              <span>Date:</span>
              <span>{format(new Date(sale.timestamp), 'MMM dd, yyyy HH:mm')}</span>
            </div>
            <div className="flex justify-between text-sm mb-2">
              <span>Cashier:</span>
              <span>
                {sale.cashier || profile?.name || 'Unknown'}
              </span>
            </div>
            {sale.customerName && (
              <div className="flex justify-between text-sm">
                <span>Customer:</span>
                <span>{sale.customerName}</span>
              </div>
            )}
          </div>

          <div className="space-y-2 mb-4">
            {sale.items.map((item, index) => (
              <div key={index}>
                <div className="flex justify-between">
                  <span className="text-sm font-medium">{item.product.name}</span>
                  <span className="text-sm font-semibold">
                    {state.settings.currency} {item.subtotal.toFixed(2)}
                  </span>
                </div>
                <div className="text-xs text-bodytext ml-2">
                  {state.settings.currency} {item.product.price.toFixed(2)} × {item.quantity}
                  {item.discount > 0 && (
                    <span className="text-success ml-2">
                      (Discount: -{state.settings.currency} {item.discount.toFixed(2)})
                    </span>
                  )}
                </div>
              </div>
            ))}
            
            {/* Free Gifts */}
            {sale.freeGifts && sale.freeGifts.length > 0 && (
              <>
                <div className="border-t border-border pt-2 mt-2">
                  <p className="text-sm font-medium text-success mb-2">🎁 Free Gifts:</p>
                  {sale.freeGifts.map((gift, index) => (
                    <div key={index} className="flex justify-between text-sm text-success">
                      <span>{gift.product.name} × {gift.quantity}</span>
                      <span>FREE</span>
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>

          <div className="border-t border-border pt-4 space-y-2">
            <div className="flex justify-between text-sm">
              <span>Subtotal:</span>
              <span>{state.settings.currency} {sale.subtotal.toFixed(2)}</span>
            </div>
            {sale.discountAmount > 0 && (
              <div className="flex justify-between text-sm text-success">
                <span>Total Discount:</span>
                <span>-{state.settings.currency} {sale.discountAmount.toFixed(2)}</span>
              </div>
            )}
            {sale.appliedDiscounts && sale.appliedDiscounts.length > 0 && (
              <div className="text-xs text-success ml-2">
                {sale.appliedDiscounts.map((discount, index) => (
                  <div key={index}>• {discount.discountName}</div>
                ))}
              </div>
            )}
            <div className="flex justify-between text-sm">
              <span>Tax:</span>
              <span>{state.settings.currency} {sale.taxAmount.toFixed(2)}</span>
            </div>
            <div className="flex justify-between text-lg font-bold border-t border-border pt-2">
              <span>Total:</span>
              <span>{state.settings.currency} {sale.total.toFixed(2)}</span>
            </div>
            {sale.payments && sale.payments.length > 0 ? (
              <div className="text-sm mt-2 space-y-0.5">
                {sale.payments.map((p, i) => (
                  <div key={i}>
                    <div className="flex justify-between">
                      <span className="capitalize">
                        {p.method === 'credit' ? 'Store credit' : p.method}
                        {p.cardLast4 ? ` ${p.cardType ? p.cardType.toUpperCase() + ' ' : ''}****${p.cardLast4}` : ''}
                        {p.method === 'digital' && p.reference ? ` (${p.reference})` : ''}
                      </span>
                      <span>{state.settings.currency} {p.amount.toFixed(2)}</span>
                    </div>
                    {p.method === 'cash' && p.tendered !== undefined && (
                      <>
                        <div className="flex justify-between text-bodytext"><span>Cash received</span><span>{state.settings.currency} {p.tendered.toFixed(2)}</span></div>
                        <div className="flex justify-between text-bodytext"><span>Change</span><span>{state.settings.currency} {p.changeGiven.toFixed(2)}</span></div>
                      </>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <div className="flex justify-between text-sm mt-2">
                <span>Payment Method:</span>
                <span className="capitalize">{sale.paymentMethod}</span>
              </div>
            )}
          </div>

          <div className="text-center mt-6 pt-4 border-t border-border">
            {state.settings.receiptFooter && <p className="text-sm whitespace-pre-wrap mb-3">{state.settings.receiptFooter}</p>}
            <p className="text-xs text-bodytext">Thank you for your business!</p>
            <p className="text-xs text-bodytext mt-1">
              {format(new Date(), 'yyyy-MM-dd HH:mm:ss')}
            </p>
          </div>
        </div>

        <div className="modal-footer no-print">
          <button
            onClick={onClose}
            className="btn btn-secondary btn-md"
          >
            Close
          </button>
          <button
            onClick={handlePrint}
            className="btn btn-primary btn-md"
          >
            Print Receipt
          </button>
        </div>        </div>

        <style>
        {`
          @media print {
            .no-print {
              display: none !important;
            }
            
            body * {
              visibility: hidden;
            }
            
            #receipt-content, #receipt-content * {
              visibility: visible;
            }
            
            #receipt-content {
              position: absolute;
              left: 0;
              top: 0;
              width: 100%;
            }
          }
        `}
        </style>
    </div>
  );
}
