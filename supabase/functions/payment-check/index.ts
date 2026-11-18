import { paymentHandler } from "../_shared/payments/handlers.ts";
import { runtimeDependencies } from "../_shared/payments/runtime.ts";

Deno.serve(paymentHandler("check", runtimeDependencies()));
