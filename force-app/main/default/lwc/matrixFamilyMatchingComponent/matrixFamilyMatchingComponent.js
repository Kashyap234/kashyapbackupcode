import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getMatrixMatches from '@salesforce/apex/MatrixFamilyMatchingController.getMatrixMatches';
import getBatchStatus from '@salesforce/apex/MatrixFamilyMatchingController.getBatchStatus';
import triggerRecalculation from '@salesforce/apex/MatrixFamilyMatchingController.triggerRecalculation';

export default class MatrixFamilyMatchingComponent extends NavigationMixin(LightningElement) {
    @api recordId; // Child record ID
    
    @track matchResults = [];
    @track batchStatus = {};
    @track isRefreshing = false;
    @track viewMode = 'detailed'; // 'table' or 'detailed'
    
    wiredMatchesResult;
    wiredBatchStatusResult;
    
    // Auto-refresh interval (30 seconds)
    refreshInterval;
    
    columns = [
        {
            label: 'Rank',
            fieldName: 'matchRank',
            type: 'number',
            cellAttributes: { alignment: 'center' },
            initialWidth: 80
        },
        {
            label: 'Family Name',
            fieldName: 'familyRecordLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'familyName' },
                target: '_blank'
            }
        },
        {
            label: 'Location',
            fieldName: 'familyLocation',
            type: 'text'
        },
        {
            label: 'Capacity',
            fieldName: 'familyCapacity',
            type: 'number',
            cellAttributes: { alignment: 'center' }
        },
        {
            label: 'Match Score',
            fieldName: 'overallScore',
            type: 'number',
            cellAttributes: {
                class: { fieldName: 'scoreClass' }
            },
            typeAttributes: {
                minimumFractionDigits: 1,
                maximumFractionDigits: 1
            }
        },
        {
            label: 'Distance (mi)',
            fieldName: 'distanceMiles',
            type: 'number',
            typeAttributes: {
                minimumFractionDigits: 1,
                maximumFractionDigits: 1
            }
        },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'View Family', name: 'view_family' },
                    { label: 'View Preference', name: 'view_preference' }
                ]
            }
        }
    ];
    
    /**
     * Wire to get matrix matches
     */
    @wire(getMatrixMatches, { childId: '$recordId' })
    wiredMatches(result) {
        this.wiredMatchesResult = result;
        if (result.data) {
            console.log('Received matrix matches:', result.data);
            this.processMatches(result.data);
        } else if (result.error) {
            console.error('Error loading matches:', result.error);
            this.showToast('Error', 'Failed to load matches: ' + 
                this.getErrorMessage(result.error), 'error');
        }
    }
    
    /**
     * Wire to get batch status
     */
    @wire(getBatchStatus)
    wiredBatchStatus(result) {
        this.wiredBatchStatusResult = result;
        if (result.data) {
            console.log('Batch status:', result.data);
            this.batchStatus = result.data;
        } else if (result.error) {
            console.error('Error loading batch status:', result.error);
        }
    }
    
    connectedCallback() {
        // Set up auto-refresh when batch is running
        this.startAutoRefresh();
    }
    
    disconnectedCallback() {
        // Clean up interval
        this.stopAutoRefresh();
    }
    
    /**
     * Start auto-refresh interval
     */
    startAutoRefresh() {
        this.refreshInterval = setInterval(() => {
            if (this.batchStatus && this.batchStatus.isRunning) {
                this.handleRefresh();
            }
        }, 30000); // 30 seconds
    }
    
    /**
     * Stop auto-refresh interval
     */
    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }
    
    /**
     * Process matches for display
     */
    processMatches(matches) {
        this.matchResults = matches.map(match => {
            return {
                ...match,
                scoreClass: this.getScoreClass(match.overallScore),
                progressVariant: this.getProgressVariant(match.overallScore),
                scoreDisplay: match.overallScore.toFixed(1),
                rankBadgeClass: this.getRankBadgeClass(match.matchRank),
                distanceAdjustment: this.calculateDistanceAdjustment(match.distanceMiles),
                calculatedDateFormatted: this.formatDateTime(match.calculatedDate),
                isTopMatch: match.matchRank === 1,
                matchRankLabel: this.getMatchRankLabel(match.matchRank)
            };
        });
    }
    
    /**
     * Handle refresh button click
     */
    handleRefresh() {
        this.isRefreshing = true;
        Promise.all([
            refreshApex(this.wiredMatchesResult),
            refreshApex(this.wiredBatchStatusResult)
        ])
        .then(() => {
            this.showToast('Success', 'Data refreshed', 'success');
        })
        .catch(error => {
            this.showToast('Error', 'Failed to refresh: ' + 
                this.getErrorMessage(error), 'error');
        })
        .finally(() => {
            this.isRefreshing = false;
        });
    }
    
    /**
     * Handle recalculation trigger
     */
    handleTriggerRecalculation() {
        this.isRefreshing = true;
        
        triggerRecalculation({ childId: this.recordId })
            .then(result => {
                this.showToast('Success', 
                    'Recalculation scheduled. Results will update in a few minutes.', 
                    'success');
                
                // Refresh after 10 seconds
                setTimeout(() => {
                    this.handleRefresh();
                }, 10000);
            })
            .catch(error => {
                this.showToast('Error', 
                    'Failed to trigger recalculation: ' + this.getErrorMessage(error), 
                    'error');
            })
            .finally(() => {
                this.isRefreshing = false;
            });
    }
    
    /**
     * Toggle view mode
     */
    toggleViewMode() {
        this.viewMode = this.viewMode === 'table' ? 'detailed' : 'table';
    }
    
    /**
     * Handle row actions
     */
    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        
        switch (action.name) {
            case 'view_family':
                this.navigateToFamily(row.familyId);
                break;
            case 'view_preference':
                this.navigateToPreference(row.preferenceId);
                break;
        }
    }
    
    /**
     * Navigate to family record
     */
    handleViewFamily(event) {
        const familyId = event.currentTarget.dataset.id;
        this.navigateToFamily(familyId);
    }
    
    navigateToFamily(familyId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: familyId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }
    
    /**
     * Navigate to preference record
     */
    handleViewPreference(event) {
        const preferenceId = event.currentTarget.dataset.id;
        this.navigateToPreference(preferenceId);
    }
    
    navigateToPreference(preferenceId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: preferenceId,
                objectApiName: 'Preference__c',
                actionName: 'view'
            }
        });
    }
    
    /**
     * Utility methods
     */
    getScoreClass(score) {
        if (score >= 80) return 'slds-text-color_success';
        if (score >= 60) return 'slds-text-color_default';
        return 'slds-text-color_warning';
    }
    
    getProgressVariant(score) {
        if (score >= 80) return 'success';
        if (score >= 60) return 'base';
        return 'warning';
    }
    
    getRankBadgeClass(rank) {
        if (rank === 1) return 'rank-badge-gold';
        if (rank === 2) return 'rank-badge-silver';
        if (rank === 3) return 'rank-badge-bronze';
        return 'rank-badge-default';
    }
    
    getMatchRankLabel(rank) {
        if (rank === 1) return '🥇 Best Match';
        if (rank === 2) return '🥈 2nd Best';
        if (rank === 3) return '🥉 3rd Best';
        return '#' + rank;
    }
    
    calculateDistanceAdjustment(miles) {
        if (miles < 10) return '+10 points (Very close)';
        if (miles < 25) return '0 points (Close)';
        if (miles < 50) return '-5 points (Moderate)';
        return '-10 points (Far)';
    }
    
    formatDateTime(dt) {
        if (!dt) return 'N/A';
        const date = new Date(dt);
        return date.toLocaleString();
    }
    
    getErrorMessage(error) {
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
    
    /**
     * Getters for template
     */
    get hasResults() {
        return this.matchResults && this.matchResults.length > 0;
    }
    
    get isTableView() {
        return this.viewMode === 'table';
    }
    
    get isDetailedView() {
        return this.viewMode === 'detailed';
    }
    
    get viewModeLabel() {
        return this.viewMode === 'table' ? 'Detailed View' : 'Table View';
    }
    
    get viewModeIcon() {
        return this.viewMode === 'table' ? 'utility:preview' : 'utility:table';
    }
    
    get isBatchRunning() {
        return this.batchStatus && this.batchStatus.isRunning;
    }
    
    get batchStatusMessage() {
        if (!this.batchStatus) return '';
        
        if (this.batchStatus.isRunning) {
            return `Batch ${this.batchStatus.status} - ${this.batchStatus.itemsProcessed} of ${this.batchStatus.totalItems} processed`;
        }
        
        if (this.batchStatus.lastRunDate) {
            return 'Last updated: ' + this.formatDateTime(this.batchStatus.lastRunDate);
        }
        
        return 'No recent batch runs';
    }
    
    get totalMatches() {
        return this.matchResults ? this.matchResults.length : 0;
    }
    
    get topScore() {
        if (!this.matchResults || this.matchResults.length === 0) return 0;
        return this.matchResults[0].overallScore.toFixed(1);
    }
    
    get avgDistance() {
        if (!this.matchResults || this.matchResults.length === 0) return 0;
        const total = this.matchResults.reduce((sum, m) => sum + m.distanceMiles, 0);
        return (total / this.matchResults.length).toFixed(1);
    }
}