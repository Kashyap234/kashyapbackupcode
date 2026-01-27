// resumeViewer.js
import { LightningElement, api, wire, track } from 'lwc';
import getResumeDetails from '@salesforce/apex/ResumeAnalyzerController.getResumeDetails';
import { refreshApex } from '@salesforce/apex';

export default class ResumeViewer extends LightningElement {
    @api recordId;
    @track resume;
    @track error;
    wiredResumeResult;

    @wire(getResumeDetails, { resumeId: '$recordId' })
    wiredResume(result) {
        this.wiredResumeResult = result;
        if (result.data) {
            this.resume = result.data;
            this.error = undefined;
            
            // Auto-refresh if still processing
            if (this.resume.Processing_Status__c === 'Pending' || 
                this.resume.Processing_Status__c === 'Processing') {
                setTimeout(() => {
                    refreshApex(this.wiredResumeResult);
                }, 3000);
            }
        } else if (result.error) {
            this.error = result.error;
            this.resume = undefined;
        }
    }

    get isProcessing() {
        return this.resume && 
               (this.resume.Processing_Status__c === 'Pending' || 
                this.resume.Processing_Status__c === 'Processing');
    }

    get isCompleted() {
        return this.resume && this.resume.Processing_Status__c === 'Completed';
    }

    get isFailed() {
        return this.resume && this.resume.Processing_Status__c === 'Failed';
    }

    get statusVariant() {
        if (this.isCompleted) return 'success';
        if (this.isFailed) return 'error';
        return 'warning';
    }

    get statusIcon() {
        if (this.isCompleted) return 'utility:success';
        if (this.isFailed) return 'utility:error';
        return 'utility:clock';
    }

    get hasSkills() {
        return this.resume && this.resume.Skills__c;
    }

    get hasExperience() {
        return this.resume && this.resume.Work_Experience__c;
    }

    get hasEducation() {
        return this.resume && this.resume.Education__c;
    }

    get hasCertifications() {
        return this.resume && this.resume.Certifications__c;
    }

    get skillsList() {
        if (!this.resume || !this.resume.Skills__c) return [];
        return this.resume.Skills__c.split(',').map(skill => skill.trim());
    }

    handleRefresh() {
        refreshApex(this.wiredResumeResult);
    }
}