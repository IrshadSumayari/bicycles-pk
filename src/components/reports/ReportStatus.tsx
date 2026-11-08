import { getErrorMessage } from '../../lib/errors';

export function ReportStatus({
  loading,
  error,
  retry,
}: {
  loading: boolean;
  error: unknown;
  retry: () => void;
}) {
  if (error)
    return (
      <div className="card p-5 space-y-3" role="alert">
        <p className="text-error">{getErrorMessage(error)}</p>
        <button
          type="button"
          className="btn btn-secondary btn-md"
          onClick={retry}
        >
          Try again
        </button>
      </div>
    );
  if (loading)
    return (
      <div className="card p-5 text-bodytext" role="status">
        Loading report…
      </div>
    );
  return null;
}
