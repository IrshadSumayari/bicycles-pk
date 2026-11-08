import type { ReportRange } from '../../lib/reportDates';

export type ReportProps = ReportRange & { currency: string; userId: string };
