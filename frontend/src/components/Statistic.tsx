import Card from "./Card";
import BrandImage from '../assets/icon-brand-recognition.svg';
import DetailedImage from '../assets/icon-detailed-records.svg';
import CustomizableImage from '../assets/icon-fully-customizable.svg';

const Statistic = () => {
  return (
    <section className="statistics">
      <div className="container">
        {/* Statistics content */}
        <div className="statistics__title">
          <h2>Advanced Statistics</h2>
          <p>
            Track how your links are performing across the web with our advanced statistics dashboard.
          </p>
        </div>

        {/* Cards */}
        <div className="statistics__cards">
          {/* Card */}
          <Card
            image={BrandImage}
            className='brand'
            title={'Brand Recognition'}
            description="Boost your brand recognition with each click. Generic links don’t mean a thing. Branded links help instil confidence in your content."
            alt='Brand Recognition'
          />
          <Card
            image={DetailedImage}
            className="detailed"
            title={'Detailed Records'}
            description="Gain insights into who is clicking your links. Knowing when and where people engage with your content helps inform better decisions."
            alt='Detailed Records'
          />
          <Card
            image={CustomizableImage}
            title={'Fully Customizable'}
            description="Improve brand awareness and content discoverability through customizable links, supercharging audience engagement."
            alt='Fully Customizable'
          />
        </div>
      </div>
    </section>
  );
}

export default Statistic;