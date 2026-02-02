import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import runReverseMatching from '@salesforce/apex/FamilyMatchingService.runReverseMatching';

export default class FamilyMatchingComponent extends NavigationMixin(LightningElement) {
    @api recordId; // Child record ID
    
    @track matchResults = [];
    @track isLoading = false;
    @track hasResults = false;
    @track errorMessage = '';
    @track viewMode = 'detailed'; // 'table' or 'detailed'
    
    // Summary statistics
    @track totalMatches = 0;
    @track averageScore = 0;
    @track topScore = 0;
    @track avgDistance = 0;
    
    columns = [
        {
            label: 'Family Name',
            fieldName: 'familyRecordLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'familyName' },
                target: '_blank'
            },
            sortable: true
        },
        {
            label: 'Capacity',
            fieldName: 'familyCapacity',
            type: 'number',
            sortable: true
        },
        {
            label: 'License Status',
            fieldName: 'licenseStatus',
            type: 'text'
        },
        {
            label: 'Match Score',
            fieldName: 'overallScore',
            type: 'number',
            cellAttributes: {
                class: { fieldName: 'scoreClass' }
            },
            sortable: true
        },
        {
            label: 'Distance (mi)',
            fieldName: 'distanceMiles',
            type: 'number',
            sortable: true
        },
        {
            label: 'Match Reasons',
            fieldName: 'matchReasonsString',
            type: 'text',
            wrapText: true
        },
        {
            label: 'Flags',
            fieldName: 'flagsString',
            type: 'text',
            wrapText: true
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
     * Toggle between table and detailed view
     */
    toggleViewMode() {
        this.viewMode = this.viewMode === 'table' ? 'detailed' : 'table';
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
    
    /**
     * Handle Run Matching button click
     */
    handleRunMatching() {
        console.log('=== Run Reverse Matching Started ===');
        console.log('Run Matching button clicked for Child ID:', this.recordId);
        console.log('Timestamp:', new Date().toISOString());
        
        this.isLoading = true;
        this.errorMessage = '';
        this.matchResults = [];
        
        console.log('Calling Apex method: runReverseMatching');
        console.log('Parameters:', { childId: this.recordId });
        
        runReverseMatching({ childId: this.recordId })
            .then(response => {
                console.log('=== Apex Response Received ===');
                console.log('Raw response:', JSON.stringify(response, null, 2));
                console.log('Response.success:', response.success);
                console.log('Response.message:', response.message);
                console.log('Response.results length:', response.results ? response.results.length : 'null');
                
                if (response.success) {
                    console.log('Success branch - Processing results...');
                    
                    if (!response.results || !Array.isArray(response.results)) {
                        console.error('ERROR: Results is not an array!', response.results);
                        this.errorMessage = 'Invalid response format: results is not an array';
                        this.showToast('Error', this.errorMessage, 'error');
                        return;
                    }
                    
                    console.log('Processing ' + response.results.length + ' results...');
                    this.processMatchResults(response.results);
                    console.log('Results processed. Match results count:', this.matchResults.length);
                    
                    console.log('Calculating summary stats...');
                    this.calculateSummaryStats();
                    
                    this.showToast('Success', 'Matching completed successfully!', 'success');
                    console.log('=== Run Reverse Matching Completed Successfully ===');
                } else {
                    console.log('Failure branch - Error from Apex');
                    console.error('Error message:', response.message);
                    
                    this.errorMessage = response.message;
                    this.showToast('Error', response.message, 'error');
                }
            })
            .catch(error => {
                console.log('=== Error Caught in Promise ===');
                console.error('Error object:', error);
                
                if (error.body) {
                    console.error('Error body:', error.body);
                    console.error('Error body.message:', error.body.message);
                }
                
                this.errorMessage = error.body ? error.body.message : 'Unknown error occurred';
                this.showToast('Error', this.errorMessage, 'error');
                console.error('Full error:', JSON.stringify(error, null, 2));
            })
            .finally(() => {
                console.log('Finally block - Setting isLoading to false');
                this.isLoading = false;
            });
    }
    
    /**
     * Process match results for display with detailed breakdowns
     */
    processMatchResults(results) {
        console.log('=== Processing Match Results ===');
        
        if (!results || !Array.isArray(results)) {
            console.error('ERROR: Results is not a valid array');
            return;
        }
        
        try {
            this.matchResults = results.map((result, index) => {
                console.log(`Processing result ${index + 1}/${results.length}:`, result);
                
                // Parse detailed scores
                const detailedScores = result.detailedScores || {};
                
                // Process high priority details
                const highPriorityDetails = this.processScoreDetails(detailedScores, 'High');
                
                // Process medium priority details
                const mediumPriorityDetails = this.processScoreDetails(detailedScores, 'Medium');
                
                // Process low priority details
                const lowPriorityDetails = this.processScoreDetails(detailedScores, 'Low');
                
                // Calculate distance adjustment display
                const distanceAdj = this.calculateDistanceAdjustment(result.distanceMiles);
                
                const processedResult = {
                    ...result,
                    matchReasonsString: result.matchReasons.join('; '),
                    flagsString: result.flags.length > 0 ? result.flags.join('; ') : 'None',
                    hasFlags: result.flags.length > 0,
                    scoreClass: this.getScoreClass(result.overallScore),
                    progressVariant: this.getProgressVariant(result.overallScore),
                    highPriorityDetails: highPriorityDetails,
                    mediumPriorityDetails: mediumPriorityDetails,
                    lowPriorityDetails: lowPriorityDetails,
                    distanceAdjustment: distanceAdj
                };
                
                return processedResult;
            });
            
            this.hasResults = this.matchResults.length > 0;
            console.log('Final processed results count:', this.matchResults.length);
            
        } catch (error) {
            console.error('ERROR in processMatchResults:', error);
            throw error;
        }
    }
    
    /**
     * Process score details for a priority level
     */
    processScoreDetails(detailedScores, priorityLevel) {
        const details = [];
        
        for (let key in detailedScores) {
            const scoreData = detailedScores[key];
            
            if (scoreData.priority === priorityLevel) {
                const scoreValue = typeof scoreData.score === 'string' 
                    ? parseFloat(scoreData.score) 
                    : (scoreData.score || 0);
                
                const detail = {
                    name: scoreData.criterionName || key,
                    weight: scoreData.weight || 0,
                    score: scoreValue,
                    scoreDisplay: `${scoreValue.toFixed(0)}%`,
                    preferenceValue: this.formatValue(scoreData.preferenceValue),
                    childValue: this.formatValue(scoreData.childValue),
                    explanation: this.generateExplanation({ ...scoreData, score: scoreValue }),
                    badgeClass: this.getScoreBadgeClass(scoreValue),
                    progressVariant: this.getProgressVariant(scoreValue)
                };
                
                details.push(detail);
            }
        }
        
        return details.length > 0 ? details : null;
    }
    
    /**
     * Format field values for display
     */
    formatValue(value) {
        if (value === null || value === undefined || value === '') {
            return 'No Preference';
        }
        
        if (typeof value === 'boolean') {
            return value ? 'Yes' : 'No';
        }
        
        if (typeof value === 'number') {
            return value.toString();
        }
        
        return String(value);
    }
    
    /**
     * Generate explanation for score
     */
    generateExplanation(scoreData) {
        const score = scoreData.score || 0;
        
        if (score === 100) {
            return '✓ Perfect match - meets all criteria';
        } else if (score >= 80) {
            return '✓ Excellent match - very close to preferences';
        } else if (score >= 60) {
            return '⚠ Good match - some differences from preference';
        } else if (score >= 40) {
            return '⚠ Partial match - notable differences';
        } else if (score > 0) {
            return '⚠ Low match - significant differences';
        } else {
            return '✗ Does not match preference';
        }
    }
    
    /**
     * Calculate distance adjustment for display
     */
    calculateDistanceAdjustment(miles) {
        if (miles < 10) return '+10 points (Very close)';
        if (miles < 25) return '0 points (Close)';
        if (miles < 50) return '-5 points (Moderate distance)';
        return '-10 points (Far distance)';
    }
    
    /**
     * Get CSS class based on score
     */
    getScoreClass(score) {
        if (score >= 80) return 'slds-text-color_success';
        if (score >= 60) return 'slds-text-color_default';
        return 'slds-text-color_warning';
    }
    
    /**
     * Get badge class based on score
     */
    getScoreBadgeClass(score) {
        if (score >= 80) return 'slds-theme_success';
        if (score >= 60) return 'slds-theme_info';
        if (score >= 40) return 'slds-theme_warning';
        return 'slds-theme_error';
    }
    
    /**
     * Get progress bar variant based on score
     */
    getProgressVariant(score) {
        if (score >= 80) return 'success';
        if (score >= 60) return 'base';
        return 'warning';
    }
    
    /**
     * Calculate summary statistics
     */
    calculateSummaryStats() {
        if (this.matchResults.length === 0) {
            this.totalMatches = 0;
            this.averageScore = 0;
            this.topScore = 0;
            this.avgDistance = 0;
            return;
        }
        
        this.totalMatches = this.matchResults.length;
        
        let totalScore = 0;
        let maxScore = 0;
        let totalDistance = 0;
        
        this.matchResults.forEach(match => {
            totalScore += match.overallScore;
            totalDistance += match.distanceMiles;
            if (match.overallScore > maxScore) {
                maxScore = match.overallScore;
            }
        });
        
        this.averageScore = (totalScore / this.matchResults.length).toFixed(1);
        this.topScore = maxScore.toFixed(1);
        this.avgDistance = (totalDistance / this.matchResults.length).toFixed(1);
    }
    
    /**
     * Handle row actions in table view
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
     * Handle view family button click
     */
    handleViewFamily(event) {
        event.preventDefault();
        const familyId = event.target.dataset.id || event.currentTarget.dataset.id;
        this.navigateToFamily(familyId);
    }
    
    /**
     * Handle view preference button click
     */
    handleViewPreference(event) {
        event.preventDefault();
        const prefId = event.target.dataset.id || event.currentTarget.dataset.id;
        this.navigateToPreference(prefId);
    }
    
    /**
     * Navigate to family record
     */
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
     * Show toast notification
     */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}