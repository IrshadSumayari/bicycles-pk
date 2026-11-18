import Swal from 'sweetalert2';

// Custom SweetAlert2 configurations that match the system design
export const swalConfig = {
  // Success toast
  success: (message: string) => {
    return Swal.fire({
      icon: 'success',
      title: 'Success!',
      text: message,
      toast: true,
      position: 'top-end',
      showConfirmButton: false,
      timer: 3000,
      timerProgressBar: true,
      background: 'var(--card)',
      color: 'var(--foreground)',
      iconColor: 'var(--primary)',
      customClass: {
        popup: 'rounded-2xl shadow-lg border border-lightsuccess backdrop-blur-xs',
        title: 'text-success font-semibold text-base',
        htmlContainer: 'text-success text-sm',
        timerProgressBar: 'bg-linear-to-r from-success to-success'
      },
      didOpen: (toast) => {
        toast.addEventListener('mouseenter', Swal.stopTimer);
        toast.addEventListener('mouseleave', Swal.resumeTimer);
      }
    });
  },

  // Error toast
  error: (message: string) => {
    return Swal.fire({
      icon: 'error',
      title: 'Error!',
      text: message,
      toast: true,
      position: 'top-end',
      showConfirmButton: false,
      timer: 4000,
      timerProgressBar: true,
      background: 'var(--card)',
      color: 'var(--foreground)',
      iconColor: 'var(--primary)',
      customClass: {
        popup: 'rounded-2xl shadow-lg border border-lighterror backdrop-blur-xs',
        title: 'text-error font-semibold text-base',
        htmlContainer: 'text-error text-sm',
        timerProgressBar: 'bg-linear-to-r from-error to-error'
      },
      didOpen: (toast) => {
        toast.addEventListener('mouseenter', Swal.stopTimer);
        toast.addEventListener('mouseleave', Swal.resumeTimer);
      }
    });
  },

  // Warning toast
  warning: (message: string) => {
    return Swal.fire({
      icon: 'warning',
      title: 'Warning!',
      text: message,
      toast: true,
      position: 'top-end',
      showConfirmButton: false,
      timer: 3500,
      timerProgressBar: true,
      background: 'var(--card)',
      color: 'var(--foreground)',
      iconColor: 'var(--primary)',
      customClass: {
        popup: 'rounded-2xl shadow-lg border border-lightwarning backdrop-blur-xs',
        title: 'text-warning font-semibold text-base',
        htmlContainer: 'text-warning text-sm',
        timerProgressBar: 'bg-linear-to-r from-warning to-warning'
      },
      didOpen: (toast) => {
        toast.addEventListener('mouseenter', Swal.stopTimer);
        toast.addEventListener('mouseleave', Swal.resumeTimer);
      }
    });
  },

  // Info toast
  info: (message: string) => {
    return Swal.fire({
      icon: 'info',
      title: 'Info',
      text: message,
      toast: true,
      position: 'top-end',
      showConfirmButton: false,
      timer: 3000,
      timerProgressBar: true,
      background: 'var(--card)',
      color: 'var(--foreground)',
      iconColor: 'var(--primary)',
      customClass: {
        popup: 'rounded-2xl shadow-lg border border-lightprimary backdrop-blur-xs',
        title: 'text-primary font-semibold text-base',
        htmlContainer: 'text-primary text-sm',
        timerProgressBar: 'bg-linear-to-r from-primary to-primary'
      },
      didOpen: (toast) => {
        toast.addEventListener('mouseenter', Swal.stopTimer);
        toast.addEventListener('mouseleave', Swal.resumeTimer);
      }
    });
  },

  // Confirmation dialog
  confirm: (title: string, text: string, confirmText: string = 'Yes, delete it!') => {
    return Swal.fire({
      title,
      text,
      icon: 'warning',
      showCancelButton: true,
      confirmButtonColor: 'var(--primary)',
      cancelButtonColor: 'var(--bodytext)',
      confirmButtonText: confirmText,
      cancelButtonText: 'Cancel',
      background: 'var(--card)',
      color: 'var(--foreground)',
      iconColor: 'var(--primary)',
      customClass: {
        popup: 'rounded-3xl shadow-2xl border border-border',
        title: 'text-link font-bold text-xl mb-2',
        htmlContainer: 'text-bodytext text-base',
        confirmButton: 'bg-primary hover:bg-primary text-white font-medium py-3 px-6 rounded-xl shadow-xs hover:shadow-md transition-all duration-200 mr-3',
        cancelButton: 'bg-lightgray hover:bg-border text-link font-medium py-3 px-6 rounded-xl transition-all duration-200',
        actions: 'gap-3 mt-6'
      },
      buttonsStyling: false
    });
  },

  // Delete confirmation
  deleteConfirm: (itemName: string) => {
    return Swal.fire({
      title: 'Are you sure?',
      text: `You won't be able to revert this! The ${itemName} will be permanently deleted.`,
      icon: 'warning',
      showCancelButton: true,
      confirmButtonColor: 'var(--primary)',
      cancelButtonColor: 'var(--bodytext)',
      confirmButtonText: 'Yes, delete it!',
      cancelButtonText: 'Cancel',
      background: 'var(--card)',
      color: 'var(--foreground)',
      iconColor: 'var(--primary)',
      customClass: {
        popup: 'rounded-3xl shadow-2xl border border-border',
        title: 'text-link font-bold text-xl mb-2',
        htmlContainer: 'text-bodytext text-base',
        confirmButton: 'bg-error hover:bg-error text-white font-medium py-3 px-6 rounded-xl shadow-xs hover:shadow-md transition-all duration-200 mr-3',
        cancelButton: 'bg-lightgray hover:bg-border text-link font-medium py-3 px-6 rounded-xl transition-all duration-200',
        actions: 'gap-3 mt-6'
      },
      buttonsStyling: false
    });
  },

  // Loading modal
  loading: (title: string = 'Processing...') => {
    return Swal.fire({
      title,
      allowOutsideClick: false,
      allowEscapeKey: false,
      showConfirmButton: false,
      background: 'var(--card)',
      color: 'var(--foreground)',
      customClass: {
        popup: 'rounded-3xl shadow-2xl border border-border',
        title: 'text-link font-semibold text-lg',
        loader: 'border-primary'
      },
      didOpen: () => {
        Swal.showLoading();
      }
    });
  },

  // Close loading
  close: () => {
    Swal.close();
  },

  // Input dialog
  input: (title: string, placeholder: string, inputType: 'text' | 'email' | 'password' | 'number' = 'text') => {
    return Swal.fire({
      title,
      input: inputType,
      inputPlaceholder: placeholder,
      showCancelButton: true,
      confirmButtonColor: 'var(--primary)',
      cancelButtonColor: 'var(--bodytext)',
      confirmButtonText: 'Submit',
      cancelButtonText: 'Cancel',
      background: 'var(--card)',
      color: 'var(--foreground)',
      customClass: {
        popup: 'rounded-3xl shadow-2xl border border-border',
        title: 'text-link font-bold text-xl mb-4',
        input: 'w-full px-4 py-3 border border-border rounded-xl focus:ring-2 focus:ring-primary focus:border-transparent transition-all duration-200 bg-card',
        confirmButton: 'bg-primary hover:bg-primary text-white font-medium py-3 px-6 rounded-xl shadow-xs hover:shadow-md transition-all duration-200 mr-3',
        cancelButton: 'bg-lightgray hover:bg-border text-link font-medium py-3 px-6 rounded-xl transition-all duration-200',
        actions: 'gap-3 mt-6'
      },
      buttonsStyling: false,
      inputValidator: (value) => {
        if (!value) {
          return 'Please enter a value!';
        }
      }
    });
  }
};

export default swalConfig;
