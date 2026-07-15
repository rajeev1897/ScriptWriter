import { LightningElement,track } from 'lwc';

const HEADLINE_TEXT = 'I code cool websites In Salesforce';

export default class ResumeMain extends LightningElement {
  @track animatedHeadline = '';
  _typed = false;

  connectedCallback() {

    
  }

  renderedCallback() {
    if (!this._typed) {
      this._typed = true;
      let i = 0;
      let temp = [];
      const type = () => {
        if (i < HEADLINE_TEXT.length) {
          if (HEADLINE_TEXT.slice(i, i+12) === 'In Salesforce') {
            temp.push('<span class="highlight">In Salesforce</span>');
            i += 12;
          } else {
            temp.push(HEADLINE_TEXT[i]);
            i++;
          }
          this.animatedHeadline = temp.join('');
        } else {
          
        setTimeout(() => {
       	i = 0;
          temp = [];
          this.animatedHeadline = '';
		}, 1000);
        }
        setTimeout(type, 100);
      };
      type();
    }
  }

  handleHeadlineHover() {
    const main = this.template.querySelector('.headline-main');
    const alt = this.template.querySelector('.headline-alt');
    if (main && alt) {
      main.classList.add('fade-out');
      alt.classList.add('fade-in');
    }
  }

  handleHeadlineOut() {
    const main = this.template.querySelector('.headline-main');
    const alt = this.template.querySelector('.headline-alt');
    if (main && alt) {
      main.classList.remove('fade-out');
      alt.classList.remove('fade-in');
    }
  }

  handleIntroHover() {
    const main = this.template.querySelector('.intro-main');
    const alt = this.template.querySelector('.intro-alt');
    if (main && alt) {
      main.classList.add('fade-out');
      alt.classList.add('fade-in');
    }
  }

  handleIntroOut() {
    const main = this.template.querySelector('.intro-main');
    const alt = this.template.querySelector('.intro-alt');
    if (main && alt) {
      main.classList.remove('fade-out');
      alt.classList.remove('fade-in');
    }
  }
}