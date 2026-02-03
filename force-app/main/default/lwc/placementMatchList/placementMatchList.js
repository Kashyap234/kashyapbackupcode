import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class PlacementMatchList extends NavigationMixin(LightningElement) {
    @api value; // Receives the 'PlacementResults' Apex object
    
    get matches() {
        if (!this.value || !this.value.matches) return [];
        
        return this.value.matches.map(m => ({
            ...m,
            scoreLabel: m.score + '% Match',
            badgeClass: m.score > 80 ? 'slds-theme_success' : 'slds-theme_warning'
        }));
    }

    handleNavigate(event) {
        const recordId = event.target.dataset.recordId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }
}