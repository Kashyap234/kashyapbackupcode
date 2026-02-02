import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import runMatching from '@salesforce/apex/ChildMatchingService.runMatching';
import updateMatchStatus from '@salesforce/apex/MatchResultController.updateMatchStatus';
import getMatchHistory from '@salesforce/apex/MatchResultController.getMatchHistory';

export default class ChildMatchingComponent extends NavigationMixin(LightningElement) {
    @api recordId; // Preference record ID
    
    @track matchResults = [];
    @track isLoading = false;
    @track hasResults = false;
    @track errorMessage = '';
    @track showStatusModal = false;
    @track selectedMatchId = '';
    @track selectedStatus = '';
    @track statusNotes = '';
    @track notSuitableReason = '';
    @track viewMode = 'detailed'; // 'table' or 'detailed'
    
    // Summary statistics
    @track totalMatches = 0;
    @track averageScore = 0;
    @track topScore = 0;
    @track avgDistance = 0;
    
    statusOptions = [
        { label: 'Recommended', value: 'Recommended' },
        { label: 'Not Suitable', value: 'Not Suitable' },
        { label: 'On Hold / Alternate', value: 'On Hold' },
        { label: 'Outreach Approved', value: 'Outreach Approved' }
    ];
    
    columns = [
        {
            label: 'Child Name',
            fieldName: 'childRecordLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'childName' },
                target: '_blank'
            },
            sortable: true
        },
        {
            label: 'Age',
            fieldName: 'childAge',
            type: 'number',
            sortable: true
        },
        {
            label: 'Gender',
            fieldName: 'childGender',
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
                    { label: 'Update Status', name: 'update_status' },
                    { label: 'View Details', name: 'view_details' }
                ]
            }
        }
    ];
    
    connectedCallback() {
        this.loadMatchHistory();
    }
    
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
        console.log('=== Run Matching Started ===');
        console.log('Run Matching button clicked for Preference ID:', this.recordId);
        console.log('Timestamp:', new Date().toISOString());
        
        this.isLoading = true;
        this.errorMessage = '';
        this.matchResults = [];
        
        console.log('Calling Apex method: runMatching');
        console.log('Parameters:', { preferenceId: this.recordId });
        
        runMatching({ preferenceId: this.recordId })
            .then(response => {
                console.log('=== Apex Response Received ===');
                console.log('Raw response:', JSON.stringify(response, null, 2));
                console.log('Response type:', typeof response);
                console.log('Response.success:', response.success);
                console.log('Response.message:', response.message);
                console.log('Response.results:', response.results);
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
                    console.log('Summary stats:', {
                        totalMatches: this.totalMatches,
                        averageScore: this.averageScore,
                        topScore: this.topScore,
                        avgDistance: this.avgDistance
                    });
                    
                    this.showToast('Success', 'Matching completed successfully!', 'success');
                    console.log('=== Run Matching Completed Successfully ===');
                } else {
                    console.log('Failure branch - Error from Apex');
                    console.error('Apex returned success=false');
                    console.error('Error message:', response.message);
                    
                    this.errorMessage = response.message;
                    this.showToast('Error', response.message, 'error');
                }
            })
            .catch(error => {
                console.log('=== Error Caught in Promise ===');
                console.error('Error object:', error);
                console.error('Error type:', typeof error);
                console.error('Error keys:', Object.keys(error));
                
                if (error.body) {
                    console.error('Error body:', error.body);
                    console.error('Error body.message:', error.body.message);
                    console.error('Error body.stackTrace:', error.body.stackTrace);
                    console.error('Error body.fieldErrors:', error.body.fieldErrors);
                    console.error('Error body.pageErrors:', error.body.pageErrors);
                }
                
                if (error.message) {
                    console.error('Error message:', error.message);
                }
                
                if (error.stack) {
                    console.error('Error stack:', error.stack);
                }
                
                this.errorMessage = error.body ? error.body.message : 'Unknown error occurred';
                this.showToast('Error', this.errorMessage, 'error');
                console.error('Full error:', JSON.stringify(error, null, 2));
                console.log('=== End Error Handler ===');
            })
            .finally(() => {
                console.log('Finally block - Setting isLoading to false');
                this.isLoading = false;
                console.log('=== Run Matching Request Complete ===');
            });
    }
    
    /**
     * Process match results for display with detailed breakdowns
     */
    processMatchResults(results) {
        console.log('=== Processing Match Results ===');
        console.log('Input results:', results);
        console.log('Input results type:', typeof results);
        console.log('Input results length:', results ? results.length : 'null');
        
        if (!results || !Array.isArray(results)) {
            console.error('ERROR: Results is not a valid array');
            return;
        }
        
        try {
            this.matchResults = results.map((result, index) => {
                console.log(`Processing result ${index + 1}/${results.length}:`, result);
                
                // Parse detailed scores
                const detailedScores = result.detailedScores || {};
                console.log(`  Detailed scores for ${result.childName}:`, detailedScores);
                
                // Process high priority details
                const highPriorityDetails = this.processScoreDetails(
                    detailedScores, 
                    'High'
                );
                console.log(`  High priority details:`, highPriorityDetails);
                
                // Process medium priority details
                const mediumPriorityDetails = this.processScoreDetails(
                    detailedScores, 
                    'Medium'
                );
                console.log(`  Medium priority details:`, mediumPriorityDetails);
                
                // Process low priority details (NEW)
                const lowPriorityDetails = this.processScoreDetails(
                    detailedScores, 
                    'Low'
                );
                console.log(`  Low priority details:`, lowPriorityDetails);
                
                // Calculate distance adjustment display
                const distanceAdj = this.calculateDistanceAdjustment(result.distanceMiles);
                console.log(`  Distance adjustment:`, distanceAdj);
                
                const processedResult = {
                    ...result,
                    matchReasonsString: result.matchReasons.join('; '),
                    flagsString: result.flags.length > 0 ? result.flags.join('; ') : 'None',
                    hasFlags: result.flags.length > 0,
                    scoreClass: this.getScoreClass(result.overallScore),
                    progressVariant: this.getProgressVariant(result.overallScore),
                    highPriorityDetails: highPriorityDetails,
                    mediumPriorityDetails: mediumPriorityDetails,
                    lowPriorityDetails: lowPriorityDetails, // NEW
                    distanceAdjustment: distanceAdj,
                    // For modal
                    matchResultId: result.matchResultId || ''
                };
                
                console.log(`  Processed result:`, processedResult);
                return processedResult;
            });
            
            this.hasResults = this.matchResults.length > 0;
            console.log('Final processed results count:', this.matchResults.length);
            console.log('hasResults:', this.hasResults);
            console.log('=== End Processing Match Results ===');
            
        } catch (error) {
            console.error('ERROR in processMatchResults:', error);
            console.error('Error message:', error.message);
            console.error('Error stack:', error.stack);
            throw error;
        }
    }
    
    /**
     * Process score details for a priority level
     */
    processScoreDetails(detailedScores, priorityLevel) {
        console.log(`Processing score details for priority: ${priorityLevel}`);
        const details = [];
        
        for (let key in detailedScores) {
            const scoreData = detailedScores[key];
            
            if (scoreData.priority === priorityLevel) {
                // Convert score to number if it's a string
                const originalScore = scoreData.score;
                const scoreValue = typeof scoreData.score === 'string' 
                    ? parseFloat(scoreData.score) 
                    : (scoreData.score || 0);
                
                if (typeof originalScore === 'string') {
                    console.log(`  Converting score from string to number: "${originalScore}" -> ${scoreValue}`);
                }
                
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
        
        console.log(`  Found ${details.length} details for priority ${priorityLevel}`);
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
        const matchingLogic = scoreData.matchingLogic;
        
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
            case 'update_status':
                this.openStatusModal(row);
                break;
            case 'view_details':
                this.navigateToChild(row.childId);
                break;
        }
    }
    
    /**
     * Handle update status button click
     */
    handleUpdateStatus(event) {
        const childId = event.target.dataset.id;
        const matchId = event.target.dataset.matchId;
        const match = this.matchResults.find(m => m.childId === childId);
        
        if (match) {
            this.openStatusModal(match);
        }
    }
    
    /**
     * Handle view child button click
     */
    handleViewChild(event) {
        event.preventDefault();
        const childId = event.target.dataset.id || event.currentTarget.dataset.id;
        this.navigateToChild(childId);
    }
    
    /**
     * Open status update modal
     */
    openStatusModal(row) {
        this.selectedMatchId = row.matchResultId;
        this.showStatusModal = true;
    }
    
    /**
     * Close status modal
     */
    closeStatusModal() {
        this.showStatusModal = false;
        this.selectedMatchId = '';
        this.selectedStatus = '';
        this.statusNotes = '';
        this.notSuitableReason = '';
    }
    
    /**
     * Handle status change
     */
    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
    }
    
    /**
     * Handle notes change
     */
    handleNotesChange(event) {
        this.statusNotes = event.target.value;
    }
    
    /**
     * Handle not suitable reason change
     */
    handleReasonChange(event) {
        this.notSuitableReason = event.target.value;
    }
    
    /**
     * Save status update
     */
    handleSaveStatus() {
        if (!this.selectedStatus) {
            this.showToast('Warning', 'Please select a status', 'warning');
            return;
        }
        
        if (this.selectedStatus === 'Not Suitable' && !this.notSuitableReason) {
            this.showToast('Warning', 'Please provide a reason for "Not Suitable"', 'warning');
            return;
        }
        
        this.isLoading = true;
        
        updateMatchStatus({
            matchResultId: this.selectedMatchId,
            newStatus: this.selectedStatus,
            notes: this.statusNotes,
            notSuitableReason: this.notSuitableReason
        })
            .then(result => {
                if (result === 'SUCCESS') {
                    this.showToast('Success', 'Status updated successfully', 'success');
                    this.closeStatusModal();
                    this.handleRunMatching(); // Refresh results
                } else {
                    this.showToast('Error', result, 'error');
                }
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
                console.error('Error updating status:', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    /**
     * Navigate to child record
     */
    navigateToChild(childId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: childId,
                objectApiName: 'Child__c',
                actionName: 'view'
            }
        });
    }
    
    /**
     * Load match history
     */
    loadMatchHistory() {
        getMatchHistory({ preferenceId: this.recordId })
            .then(results => {
                // Process and display history if needed
                console.log('Match history loaded:', results);
            })
            .catch(error => {
                console.error('Error loading match history:', error);
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
    
    get showNotSuitableReason() {
        return this.selectedStatus === 'Not Suitable';
    }
}