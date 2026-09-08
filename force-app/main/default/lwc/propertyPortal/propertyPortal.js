import { LightningElement, api, track } from 'lwc';
import getProperties from '@salesforce/apex/PropertyPortalController.getProperties';
import getCities from '@salesforce/apex/PropertyPortalController.getCities';
import getConfigurations from '@salesforce/apex/PropertyPortalController.getConfigurations';

const ALL = 'All';

const BUDGET_BANDS = [
    { value: 'any', label: 'Any budget', min: null, max: null },
    { value: 'u1', label: 'Under 1 Cr', min: null, max: 10000000 },
    { value: '1-3', label: '1 - 3 Cr', min: 10000000, max: 30000000 },
    { value: '3-6', label: '3 - 6 Cr', min: 30000000, max: 60000000 },
    { value: '6-12', label: '6 - 12 Cr', min: 60000000, max: 120000000 },
    { value: '12p', label: '12 Cr and above', min: 120000000, max: null }
];

export default class PropertyPortal extends LightningElement {
    @api brandName = 'Real Estate Property Portal';
    @api heroWatermark = 'Discover';
    @api heroHeading = 'The Legacy of an';
    @api heroHighlight = 'Address';
    @api heroSubheading =
        'A curated portfolio across Delhi, Gurugram, Noida and Faridabad - with advisors on call after hours.';
    @api footerNote = 'Prices are indicative and subject to change. RERA details available on request.';

    @track properties = [];
    cityOptions = [ALL];
    configurationOptions = [ALL];
    budgetOptions = BUDGET_BANDS;

    city = ALL;
    configuration = ALL;
    budget = 'any';

    loading = true;
    errorMessage = '';
    stats = { projects: '--', cities: '--', readyToMove: '--' };

    connectedCallback() {
        this.loadFilters();
        this.loadProperties();
    }

    async loadFilters() {
        try {
            const [cities, configurations] = await Promise.all([getCities(), getConfigurations()]);
            this.cityOptions = [ALL, ...cities];
            this.configurationOptions = [ALL, ...configurations];
        } catch (error) {
            this.cityOptions = [ALL];
            this.configurationOptions = [ALL];
        }
    }

    async loadProperties() {
        this.loading = true;
        this.errorMessage = '';
        const band = BUDGET_BANDS.find((b) => b.value === this.budget) || BUDGET_BANDS[0];

        try {
            const results = await getProperties({
                city: this.city,
                configuration: this.configuration,
                priceMin: band.min,
                priceMax: band.max
            });
            this.properties = results;
            this.updateStats(results);
        } catch (error) {
            this.properties = [];
            this.errorMessage = this.readError(error);
        } finally {
            this.loading = false;
        }
    }

    updateStats(results) {
        if (this.stats.projects === '--') {
            this.stats = {
                projects: String(results.length),
                cities: String(new Set(results.map((p) => p.city).filter(Boolean)).size),
                readyToMove: String(results.filter((p) => p.status === 'Ready to Move').length)
            };
        }
    }

    readError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Please try again in a moment, or call us and we will send the list across.'
        );
    }

    handleCity(event) {
        this.city = event.target.value;
        this.loadProperties();
    }

    handleConfiguration(event) {
        this.configuration = event.target.value;
        this.loadProperties();
    }

    handleBudget(event) {
        this.budget = event.target.value;
        this.loadProperties();
    }

    handleReset() {
        this.city = ALL;
        this.configuration = ALL;
        this.budget = 'any';
        this.loadProperties();
    }

    get hasResults() {
        return this.properties.length > 0;
    }

    get hasError() {
        return this.errorMessage !== '';
    }

    get resultsHeading() {
        if (this.city !== ALL && this.configuration !== ALL) {
            return `${this.configuration} in ${this.city}`;
        }
        if (this.city !== ALL) {
            return `Residences in ${this.city}`;
        }
        if (this.configuration !== ALL) {
            return `${this.configuration} residences`;
        }
        return 'The collection';
    }

    get resultsCaption() {
        if (this.loading) {
            return 'Curating your shortlist...';
        }
        const count = this.properties.length;
        if (count === 0) {
            return 'No matching residences';
        }
        return count === 1 ? '1 residence' : `${count} residences`;
    }
}
