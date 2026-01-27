import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import uploadAndProcessResume from '@salesforce/apex/DocumentAIResume.uploadAndProcessResume';
import getResumeDetails from '@salesforce/apex/DocumentAIResume.getResumeDetails';
import getAllResumes from '@salesforce/apex/DocumentAIResume.getAllResumes';

const ACCEPTED_FORMATS = ['.pdf', '.doc', '.docx'];
const MAX_FILE_SIZE = 10485760; // 10MB
const POLL_INTERVAL = 2000; // 2 seconds
const MAX_POLL_ATTEMPTS = 30;

export default class ResumeUploader extends LightningElement {
    @track isLoading = false;
    @track uploadProgress = 0;
    @track uploadedResumeId = null;
    @track resumeDetails = null;
    @track selectedFileName = '';
    @track processingStatus = '';
    @track showResumeListView = false;
    @track searchTerm = '';
    @track sortField = 'CreatedDate';
    @track sortDirection = 'desc';
    
    allResumesData = [];
    wiredResumesResult;
    pollInterval = null;

    // Wire service to get all resumes with refresh capability
    @wire(getAllResumes)
    wiredResumes(result) {
        this.wiredResumesResult = result;
        if (result.data) {
            this.allResumesData = result.data;
        } else if (result.error) {
            this.handleError('Error loading resumes', result.error);
        }
    }

    connectedCallback() {
        this.addDragDropListeners();
    }

    disconnectedCallback() {
        this.clearPollInterval();
    }

    // Add drag and drop functionality
    addDragDropListeners() {
        const dropZone = this.template.querySelector('.upload-section');
        if (dropZone) {
            dropZone.addEventListener('dragover', this.handleDragOver.bind(this));
            dropZone.addEventListener('drop', this.handleDrop.bind(this));
        }
    }

    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
    }

    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const files = event.dataTransfer.files;
        if (files.length > 0) {
            this.processFile(files[0]);
        }
    }

    // Handle file selection
    handleFileChange(event) {
        const file = event.target.files[0];
        if (file) {
            this.processFile(file);
        }
    }

    // Validate and process file
    processFile(file) {
        // Validate file type
        const fileExtension = '.' + file.name.split('.').pop().toLowerCase();
        if (!ACCEPTED_FORMATS.includes(fileExtension)) {
            this.showToast(
                'Invalid File Type', 
                `Please upload a valid resume file (${ACCEPTED_FORMATS.join(', ')})`, 
                'error'
            );
            this.resetFileInput();
            return;
        }

        // Validate file size
        if (file.size > MAX_FILE_SIZE) {
            this.showToast(
                'File Too Large', 
                `File size should not exceed ${this.formatFileSize(MAX_FILE_SIZE)}`, 
                'error'
            );
            this.resetFileInput();
            return;
        }

        this.selectedFileName = file.name;
        this.uploadFile(file);
    }

    // Upload file with progress tracking
    async uploadFile(file) {
        this.isLoading = true;
        this.uploadProgress = 0;
        this.processingStatus = 'Preparing upload...';
        
        try {
            const base64 = await this.readFileAsBase64(file);
            
            this.uploadProgress = 50;
            this.processingStatus = 'Uploading to Salesforce...';

            const resumeId = await uploadAndProcessResume({
                fileName: file.name,
                base64Data: base64,
                contentType: file.type
            });

            this.uploadedResumeId = resumeId;
            this.uploadProgress = 75;
            this.processingStatus = 'Processing with Document AI...';
            
            this.showToast(
                'Upload Successful', 
                'Resume uploaded! Extracting data with AI...', 
                'success'
            );
            
            // Start polling for processing completion
            this.startPolling(resumeId);
            
        } catch (error) {
            this.handleUploadError(error);
        }
    }

    // Read file as base64 with promise
    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            
            reader.onload = () => {
                const base64 = reader.result.split(',')[1];
                resolve(base64);
            };
            
            reader.onerror = () => {
                reject(new Error('Failed to read file'));
            };
            
            reader.readAsDataURL(file);
        });
    }

    // Start polling with better error handling
    startPolling(resumeId) {
        let attempts = 0;
        
        this.pollInterval = setInterval(async () => {
            attempts++;
            
            try {
                const resume = await getResumeDetails({ resumeId });
                
                if (resume.Processing_Status__c === 'Completed') {
                    this.handleProcessingComplete(resume);
                } else if (resume.Processing_Status__c === 'Failed') {
                    this.handleProcessingFailed();
                } else {
                    this.updateProcessingStatus(resume.Processing_Status__c, attempts);
                }
                
                // Check max attempts
                if (attempts >= MAX_POLL_ATTEMPTS) {
                    this.handlePollingTimeout();
                }
                
            } catch (error) {
                this.handlePollingError(error);
            }
        }, POLL_INTERVAL);
    }

    // Handle successful processing
    handleProcessingComplete(resume) {
        this.clearPollInterval();
        this.isLoading = false;
        this.uploadProgress = 100;
        this.processingStatus = 'Completed!';
        this.resumeDetails = resume;
        
        this.showToast(
            'Success', 
            'Resume data extracted and saved successfully!', 
            'success'
        );
        
        // Refresh the resumes list
        refreshApex(this.wiredResumesResult);
        
        // Reset file input
        this.resetFileInput();
        
        // Auto-scroll to details
        setTimeout(() => {
            this.scrollToElement('.resume-details-section');
        }, 300);
    }

    // Handle processing failure
    handleProcessingFailed() {
        this.clearPollInterval();
        this.isLoading = false;
        this.processingStatus = 'Processing Failed';
        
        this.showToast(
            'Processing Failed', 
            'AI extraction failed. Please try again or contact support.', 
            'error'
        );
    }

    // Update processing status with progress
    updateProcessingStatus(status, attempts) {
        const progress = 75 + (attempts / MAX_POLL_ATTEMPTS) * 20;
        this.uploadProgress = Math.min(progress, 95);
        this.processingStatus = `Analyzing document... (${status})`;
    }

    // Handle polling timeout
    handlePollingTimeout() {
        this.clearPollInterval();
        this.isLoading = false;
        this.processingStatus = 'Processing timeout';
        
        this.showToast(
            'Timeout', 
            'Processing is taking longer than expected. Please check back in a few minutes.', 
            'warning'
        );
    }

    // Clear polling interval
    clearPollInterval() {
        if (this.pollInterval) {
            clearInterval(this.pollInterval);
            this.pollInterval = null;
        }
    }

    // Handle search input
    handleSearch(event) {
        this.searchTerm = event.target.value.toLowerCase();
    }

    // Handle sorting
    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        
        if (this.sortField === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = field;
            this.sortDirection = 'asc';
        }
    }

    // Toggle resume list visibility
    handleToggleResumeList() {
        this.showResumeListView = !this.showResumeListView;
    }

    // View resume details
    async handleViewResume(event) {
        const resumeId = event.currentTarget.dataset.id;
        
        try {
            const resume = await getResumeDetails({ resumeId });
            this.resumeDetails = resume;
            this.uploadedResumeId = resumeId;
            
            // Scroll to details
            setTimeout(() => {
                this.scrollToElement('.resume-details-section');
            }, 100);
            
        } catch (error) {
            this.handleError('Failed to load resume details', error);
        }
    }

    // Clear resume details view
    handleClearView() {
        this.resumeDetails = null;
        this.uploadedResumeId = null;
        this.processingStatus = '';
        this.uploadProgress = 0;
    }

    // Upload another resume
    handleUploadAnother() {
        this.handleClearView();
        this.selectedFileName = '';
        this.scrollToElement('.upload-section');
    }

    // Reset file input
    resetFileInput() {
        const fileInput = this.template.querySelector('input[type="file"]');
        if (fileInput) {
            fileInput.value = '';
        }
        this.selectedFileName = '';
    }

    // Scroll to element
    scrollToElement(selector) {
        const element = this.template.querySelector(selector);
        if (element) {
            element.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    // Error handlers
    handleUploadError(error) {
        this.isLoading = false;
        this.uploadProgress = 0;
        this.processingStatus = '';
        this.handleError('Upload failed', error);
        this.resetFileInput();
    }

    handlePollingError(error) {
        this.clearPollInterval();
        this.isLoading = false;
        this.processingStatus = '';
        console.error('Polling error:', error);
    }

    handleError(title, error) {
        console.error(`${title}:`, error);
        this.showToast(title, this.getErrorMessage(error), 'error');
    }

    // Show toast notification
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // Get error message from exception
    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred';
    }

    // Format file size
    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
    }

    // Computed properties
    get hasResumeDetails() {
        return this.resumeDetails != null;
    }

    get filteredResumes() {
        if (!this.allResumesData) return [];
        
        let filtered = [...this.allResumesData];
        
        // Apply search filter
        if (this.searchTerm) {
            filtered = filtered.filter(resume => {
                return (resume.Candidate_Name__c?.toLowerCase().includes(this.searchTerm) ||
                        resume.Email__c?.toLowerCase().includes(this.searchTerm) ||
                        resume.Resume_File_Name__c?.toLowerCase().includes(this.searchTerm));
            });
        }
        
        // Apply sorting
        filtered.sort((a, b) => {
            let aVal = a[this.sortField];
            let bVal = b[this.sortField];
            
            if (aVal === bVal) return 0;
            if (aVal == null) return 1;
            if (bVal == null) return -1;
            
            const comparison = aVal < bVal ? -1 : 1;
            return this.sortDirection === 'asc' ? comparison : -comparison;
        });
        
        return filtered;
    }

    get hasResumes() {
        return this.filteredResumes && this.filteredResumes.length > 0;
    }

    get toggleButtonLabel() {
        return this.showResumeListView ? 'Hide List' : 'Show List';
    }

    get statusClass() {
        if (this.processingStatus.includes('Completed')) return 'status-completed';
        if (this.processingStatus.includes('Failed') || this.processingStatus.includes('timeout')) {
            return 'status-failed';
        }
        return 'status-processing';
    }

    get progressBarStyle() {
        return `width: ${this.uploadProgress}%`;
    }

    get showProgressBar() {
        return this.isLoading && this.uploadProgress > 0;
    }
}