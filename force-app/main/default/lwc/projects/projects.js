// ...existing code...
import { LightningElement } from 'lwc';

const PROJECTS = [
  {
    title: 'DWS Salesforce ChatBot',
    desc: 'Implemented messaging-in-app and web for the communication of users with the bot and live agent. When a claimant initiates a chat for the first time, their UIA information should be linked to an Account (Object) record in Salesforce to enable communication with a live agent. Utilized Messaging-In-Web, integration with 3rd party, Lightning Web Component, Apex, SLDS/CSS, Triggers, and Custom metadata.'
  },
  {
    title: 'DSPS WRA Integration',
    desc: 'Worked as both frontend and backend developer to Implement real-time communication between the application and WRA via MuleSoft. Initiate renewal process triggered by specific license events. Transmit renewal requests and handle responses seamlessly. Update license status based on renewal outcome. Ensure automated renewal process with accurate feedback. Worked directly with the Project Manager across the development department. Enable auto-population of application data using MuleSoft Integration. Worked to build community pages using Omnistudio and Vlocity. Enabled configurable to get Application information from custom metadata. Utilized the following Customer Community, Omnistudio, Vlocity, MuleSoft integration, Lightning Web Component, Apex, SLDS/CSS, Triggers, Custom metadata.'
  },
  {
    title: 'DSPS Professional Licensing Phase 2',
    desc: 'Worked as both frontend and backend developer to create and improve the application for the Wisconsin Department of Safety and Professional Services to implement and configure a project for its licensing and credentialing systems. The project provided the ability to apply for a license and renew a license.Worked directly with the Project Manager across the development department. Worked to build community pages using Omnistudio and Vlocity. Build reports using Visualforce pages and also build custom reports using lwc. Enabled configurable to get Application information from custom metadata. Enable auto-population of application data using MuleSoft Integration. Utilized the following Customer Community, Omnistudio, Vlocity, MuleSoft integration, Lightning Web Component, Apex, SLDS/CSS, Triggers, Batch classes, Visualforce pages, Custom metadata.'
  },
  {
    title: 'MHBD - Outstanding Go-live Items',
    desc: 'Worked as both frontend and backend developer to create an application for an Arizona housing company. The project provided the ability to apply for a license and renew a license. They can create an inspection and verify the license. Integrated payment gateway for US Bank for the payment. The same functionality was configured in the internal salesforce. Worked directly with the Project Manager across the development department. Worked to build community pages and configured license information using custom objects. Built reports using Visualforce pages and also built custom reports using lwc. Enabled configurable to get Application information from custom metadata and custom objects. Utilized the following Customer Community, Lightning Web Component, Apex, SLDS/CSS, Triggers, Batch classes, Visualforce pages, Custom metadata.'
  },
  {
    title: 'CTtransit Feedback Form closeout',
    desc: 'Created a lighting page that creates the cases for the Connecticut transit system the cases will be picked by the staff and resolved by communicating with the users who raised the cases. Utilized the following Customer Community, Lightning Web Component, Apex, SLDS/CSS, Triggers, Batch classes, Visualforce pages, Custom metadata.'
  },
  {
    title: 'BHF: Online Servicing Portal MVP',
    desc: 'Worked as both frontend and backend developer to create an application for an insurance company. The project uses external objects from both Heroku and Hana data services. Integrated Payment for US Bank, and built reports using Visualforce pages.Worked directly with the Project Manager across the development department. Worked to build the community to get data from external objects and integrated payment for US Bank. Built reports using Visualforce pages Integrated Salesforce with Heroku using Heroku Connect and Postgres, allowing users to access external data inside Salesforce through the community portal. Enabled configurable fund transaction services and phone and address updates by making callouts. Utilized the following Customer Community, Lightning Web Component, Apex, SLDS/CSS, Triggers, Batch classes, Visualforce pages, Custom metadata.'
  },
  {
    title: 'Iowa Agriculture Licensing',
    desc: 'Worked on both frontend and backend for resolving issues and managing all the orgs for the Iowa State Agriculture Department. Performed Issue tracking, project maintenance, deployment, and testing are some of the key functionalities. The project provided the ability to apply for a license and renew a license. They can submit semi-annual reports for their sales for feed and fertilizer. Integrated payment gateway for US Bank for the payment. The same functionality was configured in the internal salesforce.Worked to create a Portal for Iowa state for the agriculture department and provided the ability to apply for a license and renew licenses. Worked on automatic scheduling of email through apex. Worked directly with clients across the Development department to provide support and resolve any issues if required. Worked to resolve the issues, providing project maintenance, doing deployment, testing, and org maintenance Utilized the following Customer Community, Lightning Web Component, Apex, SLDS/CSS, Workflows, Process Builder, Email Templates, Triggers, Batch Classes, Visualforce pages.'
  },
  {
    title: 'Expedia - Egencia Comm',
    desc: 'Worked on both frontend and backend for creating a Portal for Travel agencies to support customers and get all updates for the events/programs/news/groups. Built a case creation for using flow and integrated LWC components in flow. Worked on custom development LWC, and lighting components.Worked to create a Portal for a Travel agency to support customers and get all updates for the events/programs/news/groups.Customized flows with custom metadata, and lightning web components and worked on Custom messaging notifications.Worked directly with project managers across the development department. Utilized the following Apex, Lightning Components, LWC, Flow, process builder, Email template.'
  },
  {
    title: 'NYC Parks:Job Training Participant (JTP) applicant tracking.',
    desc: '\Worked on both frontend and backend for creating a community to submit a form for employment to users. This community contains a 40-page application to get all the information. The team also integrated with Google address API to get the user address information. Records loaded into a custom object would be grouped by status and would send appropriate emails to users. Worked directly with clients across the Development department. Created batch classes for sending emails, displaying a user-friendly frontend to keep track of all the emails sent to users.Worked on creating a community to submit a form for employment to users and integrated Google Maps API for Address.Built an Entire community application for users to submit for Employment and scheduled the jobs based on the User Criteria. Utilized the following Apex, Lightning Components, Approval process, batch apex, process builder, Workflow rules.'
  }
];
export default class Projects extends LightningElement {
  current = 0;

  get projects() {
    // Return projects with computed style for each card
    return PROJECTS.map((proj, idx) => {
      const offset = idx - this.current;
      let style = '';
      if (offset === 0) {
        style = 'z-index:3; transform: scale(1) translateX(0); opacity:1;';
      } else if (offset < 0) {
        style = `z-index:2; transform: scale(0.92) translateX(-${Math.abs(offset)*30}px); opacity:0.5;`;
      } else if (offset > 0) {
        style = `z-index:1; transform: scale(0.92) translateX(${offset*30}px); opacity:0.5;`;
      }
      return { ...proj, idx, style };
    });
  }

  get currentProject() {
    return this.projects[this.current];
  }

  prevProject() {
    if (this.current > 0) {
      this.current--;
    }
  }

  nextProject() {
    if (this.current < PROJECTS.length - 1) {
      this.current++;
    }
  }
}